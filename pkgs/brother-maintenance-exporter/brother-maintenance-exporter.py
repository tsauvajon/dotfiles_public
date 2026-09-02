#!/usr/bin/env python3
"""Brother maintenance-info Prometheus exporter.

The Brother DCP-L2620DW hides consumable levels behind the standard
Printer-MIB when a third-party toner cartridge is installed
(prtMarkerSuppliesLevel = -3 "some remaining", MaxCapacity = -2). Three
private/auxiliary sources fill those gaps:

    brInfoMaintenance .1.3.6.1.4.1.2435.2.3.9.4.2.1.5.5.8.0
        Octet string of 7-byte records: key(1B) type(2B, always 01 04)
        value(4B big-endian). Key mapping follows python-brother
        (github.com/bieniu/brother, VALUES_LASER_MAINTENANCE); keys listed
        in PERCENT_VALUES there are hundredths of a percent, so divide by 100.

    Paper-tray table .1.3.6.1.4.1.2435.2.4.3.99.3.1.2.1.2.N
        Tab-separated ASCII rows: NAME TYPE SIZE ID MAX REMAIN. Row N=2 is
        the header; N>=3 are trays. The REMAIN column is pinned at 100 on
        this firmware (even with the tray empty), so only MAX is trusted.

    prtInputTable .1.3.6.1.2.1.43.8.2.1 (RFC 3805)
        prtInputCurrentLevel (.10): -3 "some remaining" while the tray has
        paper, 0 once a feed attempt finds it empty. This is the only real
        paper-presence signal the firmware exposes.

    Active alert .1.3.6.1.2.1.43.18.1.1.8.1.1 (prtAlertDescription)
        Localized LCD status line, e.g. "Veille" while in sleep.
"""

import argparse
import re
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAINTENANCE_OID = ".1.3.6.1.4.1.2435.2.3.9.4.2.1.5.5.8.0"
TRAY_TABLE_OID = ".1.3.6.1.4.1.2435.2.4.3.99.3.1.2.1.2"
ALERT_DESCRIPTION_OID = ".1.3.6.1.2.1.43.18.1.1.8.1.1"
INPUT_LEVEL_OID = ".1.3.6.1.2.1.43.8.2.1.10"
INPUT_DESCRIPTION_OID = ".1.3.6.1.2.1.43.8.2.1.13"

KEYS = {
    0x11: "brother_drum_page_count",
    0x31: "brother_black_toner_status",
    0x41: "brother_drum_remaining_percent",
    0x63: "brother_drum_status",
    0x6F: "brother_black_toner_remaining_percent",
    0x81: "brother_black_toner_level_percent",
}
PERCENT_KEYS = {0x41, 0x6F}

HELP = {
    "brother_drum_page_count": "Pages printed since the drum unit was reset",
    "brother_black_toner_status": "Black toner status code per Brother maintenance info (1=OK)",
    "brother_drum_remaining_percent": "Drum unit remaining life estimate (percent)",
    "brother_drum_status": "Drum unit status code per Brother maintenance info (1=OK)",
    "brother_black_toner_remaining_percent": (
        "Black toner remaining estimate (percent), from Brother private "
        "maintenance info; firmware may not track non-genuine cartridges"
    ),
    "brother_black_toner_level_percent": (
        "Coarse black toner level (percent) from Brother private maintenance info"
    ),
    "brother_paper_input_level": (
        "Paper presence per input tray (RFC 3805 prtInputCurrentLevel): "
        "-3 some remaining, 0 empty, -1 other, -2 unknown, positive = sheets"
    ),
    "brother_paper_tray_capacity_sheets": "Rated sheet capacity of a paper tray",
    "brother_printer_status_message": (
        "Current printer LCD/alert message (always 1); the message itself is "
        "the label, e.g. Veille while sleeping"
    ),
}


def clean_display_string(raw: str) -> str:
    """net-snmp renders DisplayStrings as '"text with \\n escapes"'."""
    return raw.strip().strip('"').replace("\\n", " ").replace("\\t", "\t").strip()


def snmp_get(snmp_host: str, community: str, oid: str) -> tuple[str, str]:
    out = subprocess.run(
        ["snmpget", "-v1", "-c", community, "-On", "-t1", "-r1", snmp_host, oid],
        capture_output=True,
        text=True,
        timeout=20,
        check=True,
    ).stdout
    match = re.search(r"=\s*([\w-]+):\s*(.*)", out, re.S)
    if not match:
        raise ValueError(f"unexpected snmpget response: {out[:80]}")
    kind, raw = match.group(1), match.group(2)
    if kind == "STRING":
        return kind, clean_display_string(raw)
    return kind, raw.strip()


def parse_maintenance(snmp_host: str, community: str) -> list[tuple[str, int]]:
    kind, raw = snmp_get(snmp_host, community, MAINTENANCE_OID)
    if kind != "Hex-STRING":
        raise ValueError(f"unexpected maintenance response: {raw[:60]}")
    data = bytes.fromhex("".join(re.findall(r"[0-9A-Fa-f]{2}", raw)))
    records = []
    i = 0
    while i < len(data) - 6:
        key = data[i]
        if data[i + 1 : i + 3] != b"\x01\x04":
            break
        records.append((key, int.from_bytes(data[i + 3 : i + 7], "big")))
        i += 7
    return records


def parse_trays(snmp_host: str, community: str) -> list[dict[str, str]]:
    out = subprocess.run(
        ["snmpwalk", "-v1", "-c", community, "-On", "-t1", "-r1", snmp_host, TRAY_TABLE_OID],
        capture_output=True,
        text=True,
        timeout=20,
        check=True,
    ).stdout
    trays = []
    for line in out.splitlines():
        if "= STRING:" not in line:
            continue
        row = clean_display_string(line.split("STRING:", 1)[1])
        fields = [f.strip() for f in row.split("\t") if f.strip()]
        if len(fields) != 6 or fields[0] == "NAME":
            continue
        trays.append(
            {
                "name": fields[0],
                "type": fields[1],
                "size": fields[2],
                "capacity": fields[4],
                # fields[5] REMAIN is pinned at 100 on this firmware; ignored.
            }
        )
    return trays


def parse_inputs(snmp_host: str, community: str) -> list[dict[str, str | int]]:
    """prtInputTable rows: level (.10) + description (.13), joined by row index."""
    levels = {}
    names = {}
    for oid, sink in ((INPUT_LEVEL_OID, levels), (INPUT_DESCRIPTION_OID, names)):
        out = subprocess.run(
            ["snmpwalk", "-v1", "-c", community, "-On", "-t1", "-r1", snmp_host, oid],
            capture_output=True,
            text=True,
            timeout=20,
            check=True,
        ).stdout
        for line in out.splitlines():
            match = re.search(r"\.(\d+) = \w+: (.*)", line)
            if not match:
                continue
            row, value = match.group(1), match.group(2)
            if sink is levels:
                sink[row] = int(value)
            else:
                sink[row] = clean_display_string(value)
    return [
        {"input": names.get(row, f"input{row}"), "level": levels[row]}
        for row in sorted(levels)
    ]


def render_metrics(snmp_host: str, community: str) -> str:
    lines = [
        "# HELP brother_maintenance_up Whether the last printer scrape succeeded",
        "# TYPE brother_maintenance_up gauge",
    ]
    try:
        records = parse_maintenance(snmp_host, community)
        trays = parse_trays(snmp_host, community)
        inputs = parse_inputs(snmp_host, community)
        _, message = snmp_get(snmp_host, community, ALERT_DESCRIPTION_OID)
        up = "1"
    except Exception as exc:
        print(f"scrape failed: {exc}")
        lines.append("brother_maintenance_up 0")
        return "\n".join(lines) + "\n"

    lines.append("brother_maintenance_up 1")
    for key, val in records:
        name = KEYS.get(key)
        if name is None:
            continue
        if key in PERCENT_KEYS:
            val = round(val / 100)
        lines.append(f"# HELP {name} {HELP[name]}")
        lines.append(f"# TYPE {name} gauge")
        lines.append(f"{name} {val}")

    if trays:
        lines.append(f"# HELP brother_paper_tray_capacity_sheets {HELP['brother_paper_tray_capacity_sheets']}")
        lines.append("# TYPE brother_paper_tray_capacity_sheets gauge")
    for tray in trays:
        labels = f'name="{tray["name"]}",type="{tray["type"]}",size="{tray["size"]}"'
        lines.append(f'brother_paper_tray_capacity_sheets{{{labels}}} {tray["capacity"]}')

    if inputs:
        lines.append(f"# HELP brother_paper_input_level {HELP['brother_paper_input_level']}")
        lines.append("# TYPE brother_paper_input_level gauge")
    for inp in inputs:
        lines.append(f'brother_paper_input_level{{input="{inp["input"]}"}} {inp["level"]}')

    if message:
        safe = message.replace("\\", "\\\\").replace('"', '\\"')
        lines.append(f"# HELP brother_printer_status_message {HELP['brother_printer_status_message']}")
        lines.append("# TYPE brother_printer_status_message gauge")
        lines.append(f'brother_printer_status_message{{message="{safe}"}} 1')
    return "\n".join(lines) + "\n"


class Handler(BaseHTTPRequestHandler):
    snmp_host = "192.168.0.158"
    community = "public"

    def do_GET(self):
        if self.path != "/metrics":
            self.send_error(404)
            return
        body = render_metrics(self.snmp_host, self.community).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--bind", required=True, help="address:port to listen on")
    ap.add_argument("--snmp-host", default="192.168.0.158")
    ap.add_argument("--community", default="public")
    args = ap.parse_args()
    host, port = args.bind.rsplit(":", 1)
    Handler.snmp_host = args.snmp_host
    Handler.community = args.community
    ThreadingHTTPServer((host, int(port)), Handler).serve_forever()


if __name__ == "__main__":
    main()
