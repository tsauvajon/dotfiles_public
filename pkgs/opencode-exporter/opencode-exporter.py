#!/usr/bin/env python3
"""Prometheus exporter for an OpenCode shared server.

Polls the HTTP API of an `opencode serve` instance (health, projects and
per-directory session lists) and exposes aggregate gauges in the Prometheus
text exposition format. Standard library only.

The exporter answers /metrics even while the OpenCode server is down: it
reports opencode_up 0 instead of failing, so a systemd health check on
/metrics never loop-restarts it.
"""

import argparse
import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import URLError
from urllib.parse import quote
from urllib.request import urlopen

ACTIVE_WINDOW_SECONDS = 86400.0
REQUEST_TIMEOUT_SECONDS = 10.0

TOKEN_TYPES = ("input", "output", "reasoning", "cache_read", "cache_write")


class ServerError(Exception):
    pass


def fetch_json(server_url, path):
    url = f"{server_url}{path}"
    try:
        with urlopen(url, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            if response.status != 200:
                raise ServerError(f"{url}: HTTP {response.status}")
            return json.load(response)
    except (URLError, OSError, json.JSONDecodeError) as error:
        raise ServerError(f"{url}: {error}") from error


def escape_label(value):
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def format_metric(name, help_text, metric_type, samples):
    """Render one metric family as exposition-format lines."""
    lines = [f"# HELP {name} {help_text}", f"# TYPE {name} {metric_type}"]
    for labels, value in samples:
        rendered = "".join(f'{key}="{escape_label(str(val))}",' for key, val in labels)
        series = f"{name}{{{rendered}}}" if rendered else name
        lines.append(f"{series} {value}")
    return lines


def model_samples(values, cast):
    return [
        (
            [("provider", provider), ("model", model_id)],
            cast(values[(provider, model_id)]),
        )
        for provider, model_id in sorted(values)
    ]


def model_token_samples(values):
    return [
        (
            [("provider", provider), ("model", model_id), ("type", token_type)],
            values[(provider, model_id)][token_type],
        )
        for provider, model_id in sorted(values)
        for token_type in TOKEN_TYPES
    ]


def collect_sessions(server_url):
    """Return (projects, sessions) with sessions deduplicated across scopes."""
    projects = fetch_json(server_url, "/project")
    directories = set()
    for project in projects:
        worktree = project.get("worktree")
        if worktree:
            directories.add(worktree)
        directories.update(project.get("sandboxes") or [])

    sessions_by_id = {}
    for directory in sorted(directories):
        scoped = fetch_json(server_url, f"/session?directory={quote(directory, safe='')}")
        for session in scoped:
            sessions_by_id[session["id"]] = session

    # Sessions outside any known project scope (the server working directory).
    for session in fetch_json(server_url, "/session"):
        sessions_by_id.setdefault(session["id"], session)

    return projects, list(sessions_by_id.values())


def collect(server_url):
    started = time.monotonic()

    health = fetch_json(server_url, "/global/health")
    if not isinstance(health, dict) or not health.get("healthy"):
        raise ServerError(f"/global/health did not report healthy: {health!r}")

    projects, sessions = collect_sessions(server_url)

    token_totals = {token_type: 0 for token_type in TOKEN_TYPES}
    model_cost = {}
    model_sessions = {}
    model_tokens = {}
    cost_total = 0.0
    lines_added_total = 0
    lines_deleted_total = 0
    last_update_seconds = 0.0
    active_24h = 0
    now_ms = time.time() * 1000.0

    for session in sessions:
        tokens = session.get("tokens") or {}
        cache = tokens.get("cache") or {}
        model = session.get("model") or {}
        model_key = (
            str(model.get("providerID") or "unknown"),
            str(model.get("id") or "unknown"),
        )
        model_tokens.setdefault(model_key, {token_type: 0 for token_type in TOKEN_TYPES})
        session_tokens = {
            "input": int(tokens.get("input") or 0),
            "output": int(tokens.get("output") or 0),
            "reasoning": int(tokens.get("reasoning") or 0),
            "cache_read": int(cache.get("read") or 0),
            "cache_write": int(cache.get("write") or 0),
        }
        for token_type, value in session_tokens.items():
            token_totals[token_type] += value
            model_tokens[model_key][token_type] += value

        cost = float(session.get("cost") or 0.0)
        cost_total += cost
        model_cost[model_key] = model_cost.get(model_key, 0.0) + cost
        model_sessions[model_key] = model_sessions.get(model_key, 0) + 1

        summary = session.get("summary") or {}
        lines_added_total += int(summary.get("additions") or 0)
        lines_deleted_total += int(summary.get("deletions") or 0)

        updated_ms = float((session.get("time") or {}).get("updated") or 0.0)
        last_update_seconds = max(last_update_seconds, updated_ms / 1000.0)
        if updated_ms > 0 and now_ms - updated_ms <= ACTIVE_WINDOW_SECONDS * 1000.0:
            active_24h += 1

    duration = time.monotonic() - started
    version = str(health.get("version") or "unknown")

    families = [
        format_metric(
            "opencode_up",
            "1 when the OpenCode server answered its health endpoint.",
            "gauge",
            [([], 1)],
        ),
        format_metric(
            "opencode_server_info",
            "OpenCode server build info; value is always 1.",
            "gauge",
            [([("version", version)], 1)],
        ),
        format_metric(
            "opencode_projects_total",
            "Number of projects known to the OpenCode server.",
            "gauge",
            [([], len(projects))],
        ),
        format_metric(
            "opencode_sessions_total",
            "Number of sessions across all project scopes.",
            "gauge",
            [([], len(sessions))],
        ),
        format_metric(
            "opencode_sessions_active_24h",
            "Sessions updated within the last 24 hours.",
            "gauge",
            [([], active_24h)],
        ),
        format_metric(
            "opencode_session_tokens_total",
            "Cumulative tokens summed across all sessions.",
            "counter",
            [([("type", token_type)], token_totals[token_type]) for token_type in sorted(token_totals)],
        ),
        format_metric(
            "opencode_model_tokens_total",
            "Cumulative tokens per provider/model and token type.",
            "counter",
            model_token_samples(model_tokens),
        ),
        format_metric(
            "opencode_session_cost_usd_total",
            "Cumulative session cost in USD summed across all sessions.",
            "counter",
            [([], round(cost_total, 6))],
        ),
        format_metric(
            "opencode_model_cost_usd_total",
            "Cumulative session cost in USD per provider/model.",
            "counter",
            model_samples(model_cost, lambda value: round(value, 6)),
        ),
        format_metric(
            "opencode_model_sessions_total",
            "Sessions started per provider/model.",
            "counter",
            model_samples(model_sessions, int),
        ),
        format_metric(
            "opencode_session_lines_added_total",
            "Cumulative lines added across all sessions.",
            "counter",
            [([], lines_added_total)],
        ),
        format_metric(
            "opencode_session_lines_deleted_total",
            "Cumulative lines deleted across all sessions.",
            "counter",
            [([], lines_deleted_total)],
        ),
        format_metric(
            "opencode_last_session_update_timestamp_seconds",
            "Unix timestamp of the most recent session update.",
            "gauge",
            [([], last_update_seconds)],
        ),
        format_metric(
            "opencode_exporter_scrape_duration_seconds",
            "Time the last API collection took.",
            "gauge",
            [([], round(duration, 6))],
        ),
    ]

    lines = []
    for family_lines in families:
        lines.extend(family_lines)
    lines.append("")
    return "\n".join(lines)


class MetricsHandler(BaseHTTPRequestHandler):
    server_version = "opencode-exporter/1.0.0"
    exporter_server_url = None

    def do_GET(self):
        if self.path != "/metrics":
            self.send_error(404)
            return
        try:
            body = collect(self.exporter_server_url).encode()
        except ServerError as error:
            body = (
                "# HELP opencode_up 1 when the OpenCode server answered its health endpoint.\n"
                "# TYPE opencode_up gauge\n"
                "opencode_up 0\n"
                f"# HELP opencode_exporter_last_collection_error_info Last collection error.\n"
                "# TYPE opencode_exporter_last_collection_error_info gauge\n"
                f'opencode_exporter_last_collection_error_info{{error="{escape_label(str(error))}"}} 1\n'
            ).encode()
        except Exception as error:  # pragma: no cover - defensive
            print(f"collection failed: {error}", file=sys.stderr)
            self.send_error(500)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


def parse_bind(value):
    host, separator, port_text = value.rpartition(":")
    if not separator or not host:
        raise argparse.ArgumentTypeError("bind must be HOST:PORT")
    try:
        port = int(port_text)
    except ValueError as error:
        raise argparse.ArgumentTypeError("bind port must be an integer") from error
    if not 0 < port < 65536:
        raise argparse.ArgumentTypeError("bind port out of range")
    return host, port


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--bind",
        type=parse_bind,
        default=("127.0.0.1", 9630),
        metavar="HOST:PORT",
        help="address to serve metrics on (default: 127.0.0.1:9630)",
    )
    parser.add_argument(
        "--server-url",
        default="http://127.0.0.1:4096",
        metavar="URL",
        help="base URL of the shared OpenCode server (default: %(default)s)",
    )
    args = parser.parse_args()

    handler = MetricsHandler
    handler.exporter_server_url = args.server_url.rstrip("/")
    server = ThreadingHTTPServer(args.bind, handler)
    host, port = args.bind
    print(f"serving metrics on http://{host}:{port}/metrics", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
