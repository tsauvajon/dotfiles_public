#!/usr/bin/env python3
"""Prometheus exporter for an OpenCode shared server.

Polls the HTTP API of an `opencode serve` instance (health, projects and
per-directory session lists) and exposes aggregate gauges in the Prometheus
text exposition format. Standard library only.

The exporter also collects subscription quota state (ai_subscription_quota_*)
by querying each provider's usage endpoint directly, using the credentials
from the local OpenCode auth file. It never refreshes OAuth tokens itself;
when an access token is stale the affected subscription reports
ai_subscription_quota_up 0 until the OpenCode server refreshes it.

The exporter answers /metrics even while the OpenCode server is down: it
reports opencode_up 0 instead of failing, so a systemd health check on
/metrics never loop-restarts it.
"""

import argparse
import json
import os
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen

ACTIVE_WINDOW_SECONDS = 86400.0
REQUEST_TIMEOUT_SECONDS = 10.0

TOKEN_TYPES = ("input", "output", "reasoning", "cache_read", "cache_write")

OPENAI_USAGE_URL = "https://chatgpt.com/backend-api/wham/usage"
ZAI_QUOTA_URL = "https://api.z.ai/api/monitor/usage/quota/limit"
QUOTA_CACHE_TTL_SECONDS = 55.0
OPENAI_TOKEN_MARGIN_SECONDS = 60.0

# Z.AI's response enum uses unit=6 for the weekly model-credit window and
# unit=5 for monthly tool quotas.
ZAI_UNIT_ABBREVIATIONS = {3: "h", 4: "d", 5: "mo", 6: "w"}
ZAI_TYPE_FALLBACK_WINDOWS = {"TOKENS_LIMIT": "5h", "TIME_LIMIT": "1mo"}

# Provider label values keyed by subscription, so quota and usage series can be
# joined in dashboards.
QUOTA_PROVIDER_LABELS = {"openai": "openai", "zai-coding-plan": "zai"}


class ServerError(Exception):
    pass


class QuotaError(Exception):
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


def fetch_provider_json(url, headers):
    request = Request(url, headers=headers)
    try:
        with urlopen(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            if response.status != 200:
                raise QuotaError(f"HTTP {response.status}")
            return json.load(response)
    except HTTPError as error:
        raise QuotaError(f"HTTP {error.code}") from error
    except (URLError, OSError) as error:
        raise QuotaError("connection failed") from error
    except json.JSONDecodeError as error:
        raise QuotaError("invalid JSON") from error


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


def default_auth_path():
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "share"
    )
    return os.path.join(data_home, "opencode", "auth.json")


def clamp01(value):
    return max(0.0, min(1.0, value))


def window_label_from_seconds(seconds):
    if seconds <= 0:
        return "unknown"
    known = {18000: "5h", 86400: "1d", 604800: "1w", 2592000: "1mo"}
    if seconds in known:
        return known[seconds]
    if seconds % 86400 == 0:
        return f"{seconds // 86400}d"
    if seconds % 3600 == 0:
        return f"{seconds // 3600}h"
    return f"{seconds}s"


def zai_window_label(entry):
    unit = entry.get("unit")
    number = entry.get("number")
    abbreviation = ZAI_UNIT_ABBREVIATIONS.get(unit if isinstance(unit, int) else None)
    if abbreviation and isinstance(number, int) and 0 < number < 100:
        return f"{number}{abbreviation}"
    fallback = ZAI_TYPE_FALLBACK_WINDOWS.get(str(entry.get("type") or ""))
    return fallback or "unknown"


def parse_openai_usage(payload):
    if not isinstance(payload, dict):
        raise QuotaError("openai: invalid payload")
    rate_limit = payload.get("rate_limit")
    if not isinstance(rate_limit, dict):
        raise QuotaError("openai: no rate limit data")
    plan = str(payload.get("plan_type") or "unknown")
    windows = []
    for key in ("primary_window", "secondary_window"):
        entry = rate_limit.get(key)
        if not isinstance(entry, dict):
            continue
        used_ratio = clamp01(float(entry.get("used_percent") or 0.0) / 100.0)
        window_seconds = int(entry.get("limit_window_seconds") or 0)
        windows.append(
            {
                "window": window_label_from_seconds(window_seconds),
                "used_ratio": used_ratio,
                "remaining_ratio": clamp01(1.0 - used_ratio),
                "reset_seconds": float(entry.get("reset_at") or 0.0),
                "limit_credits": None,
                "used_credits": None,
            }
        )
    windows.sort(key=lambda window: window["window"])
    return plan, windows


def parse_zai_quota(payload):
    if not isinstance(payload, dict) or not isinstance(payload.get("data"), dict):
        raise QuotaError("zai: invalid payload")
    data = payload["data"]
    limits = data.get("limits")
    if not isinstance(limits, list):
        raise QuotaError("zai: no limits data")
    plan = str(data.get("level") or "unknown")
    windows_by_label = {}
    for limit in limits:
        if not isinstance(limit, dict):
            continue
        limit_value = float(limit.get("usage") or 0.0)
        used_value = float(limit.get("currentValue") or 0.0)
        remaining_value = float(limit.get("remaining") or 0.0)
        percentage = float(limit.get("percentage") or 0.0)
        if limit_value > 0:
            used_ratio = clamp01(used_value / limit_value)
            remaining_ratio = clamp01(remaining_value / limit_value)
        else:
            used_ratio = clamp01(percentage / 100.0)
            remaining_ratio = clamp01(1.0 - used_ratio)
        credits = str(limit.get("type") or "") == "CREDIT_LIMIT"
        window = {
            "window": zai_window_label(limit),
            "used_ratio": used_ratio,
            "remaining_ratio": remaining_ratio,
            "reset_seconds": float(limit.get("nextResetTime") or 0.0) / 1000.0,
            "limit_credits": limit_value if credits else None,
            "used_credits": used_value if credits else None,
        }
        existing = windows_by_label.get(window["window"])
        if existing is not None and not (existing["limit_credits"] is None and credits):
            continue
        windows_by_label[window["window"]] = window
    windows = sorted(windows_by_label.values(), key=lambda window: window["window"])
    return plan, windows


def collect_openai_quota(auth_entry, now_ms):
    if not isinstance(auth_entry, dict) or auth_entry.get("type") != "oauth":
        raise QuotaError("openai: not authorized via oauth")
    access = auth_entry.get("access")
    account_id = auth_entry.get("accountId")
    if not access or not account_id:
        raise QuotaError("openai: missing token or account id")
    expires_ms = float(auth_entry.get("expires") or 0.0)
    if expires_ms <= 0.0:
        raise QuotaError("openai: no access token expiry")
    if expires_ms < now_ms + OPENAI_TOKEN_MARGIN_SECONDS * 1000.0:
        raise QuotaError("openai: stale access token")
    payload = fetch_provider_json(
        OPENAI_USAGE_URL,
        headers={
            "Authorization": f"Bearer {access}",
            "ChatGPT-Account-Id": str(account_id),
            "User-Agent": "codex-cli",
        },
    )
    return parse_openai_usage(payload)


def collect_zai_quota(auth_entry):
    if not isinstance(auth_entry, dict) or not auth_entry.get("key"):
        raise QuotaError("zai: no api key")
    payload = fetch_provider_json(
        ZAI_QUOTA_URL,
        headers={"Authorization": str(auth_entry["key"])},
    )
    return parse_zai_quota(payload)


quota_cache = {}
quota_lock = threading.Lock()


def refresh_quotas(auth_path):
    """Refresh the per-subscription quota cache within its TTL."""
    try:
        with open(auth_path, encoding="utf-8") as handle:
            auth = json.load(handle)
    except FileNotFoundError:
        return
    except (OSError, json.JSONDecodeError) as error:
        print(f"quota auth file unreadable: {error}", file=sys.stderr)
        return

    now_ms = time.time() * 1000.0
    collectors = (
        ("openai", lambda: collect_openai_quota(auth.get("openai"), now_ms)),
        (
            "zai-coding-plan",
            lambda: collect_zai_quota(auth.get("zai-coding-plan")),
        ),
    )
    with quota_lock:
        for subscription, collector in collectors:
            cached = quota_cache.get(subscription)
            if cached and (
                time.monotonic() - cached["fetched_monotonic"] < QUOTA_CACHE_TTL_SECONDS
            ):
                continue
            entry = {"fetched_monotonic": time.monotonic()}
            try:
                plan, windows = collector()
                entry.update(
                    plan=plan,
                    windows=windows,
                    error=None,
                    success_wall=time.time(),
                )
            except QuotaError as error:
                entry.update(
                    plan=None,
                    windows=[],
                    error=str(error),
                    success_wall=(cached or {}).get("success_wall", 0.0),
                )
            quota_cache[subscription] = entry


def quota_families():
    samples_up = []
    samples_info = []
    samples_last = []
    samples_remaining = []
    samples_used = []
    samples_reset = []
    samples_limit_credits = []
    samples_used_credits = []

    for subscription in sorted(quota_cache):
        entry = quota_cache[subscription]
        labels = [
            ("subscription", subscription),
            ("provider", QUOTA_PROVIDER_LABELS.get(subscription, subscription)),
        ]
        samples_up.append((labels, 0.0 if entry["error"] else 1.0))
        if entry["success_wall"] > 0:
            samples_last.append((labels, entry["success_wall"]))
        if entry["plan"]:
            samples_info.append((labels + [("plan", entry["plan"])], 1.0))
        for window_entry in entry["windows"]:
            window_labels = labels + [("window", window_entry["window"])]
            samples_remaining.append(
                (window_labels, round(window_entry["remaining_ratio"], 6))
            )
            samples_used.append((window_labels, round(window_entry["used_ratio"], 6)))
            if window_entry["reset_seconds"] > 0:
                samples_reset.append((window_labels, window_entry["reset_seconds"]))
            if window_entry["limit_credits"] is not None:
                samples_limit_credits.append(
                    (window_labels, window_entry["limit_credits"])
                )
                samples_used_credits.append(
                    (window_labels, window_entry["used_credits"])
                )

    return [
        format_metric(
            "ai_subscription_quota_up",
            "1 when the subscription's quota endpoint answered successfully.",
            "gauge",
            samples_up,
        ),
        format_metric(
            "ai_subscription_info",
            "Subscription plan information; value is always 1.",
            "gauge",
            samples_info,
        ),
        format_metric(
            "ai_subscription_quota_last_scrape_timestamp_seconds",
            "Unix timestamp of the last successful quota collection.",
            "gauge",
            samples_last,
        ),
        format_metric(
            "ai_subscription_quota_remaining_ratio",
            "Remaining subscription quota as a 0..1 ratio per window.",
            "gauge",
            samples_remaining,
        ),
        format_metric(
            "ai_subscription_quota_used_ratio",
            "Used subscription quota as a 0..1 ratio per window.",
            "gauge",
            samples_used,
        ),
        format_metric(
            "ai_subscription_quota_reset_timestamp_seconds",
            "Unix timestamp of the next quota window reset.",
            "gauge",
            samples_reset,
        ),
        format_metric(
            "ai_subscription_quota_limit_credits",
            "Subscription quota window allowance in credits.",
            "gauge",
            samples_limit_credits,
        ),
        format_metric(
            "ai_subscription_quota_used_credits",
            "Subscription quota window consumption in credits.",
            "gauge",
            samples_used_credits,
        ),
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


def collect(server_url, auth_path):
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

    refresh_quotas(auth_path)
    families.extend(quota_families())

    lines = []
    for family_lines in families:
        lines.extend(family_lines)
    lines.append("")
    return "\n".join(lines)


class MetricsHandler(BaseHTTPRequestHandler):
    server_version = "opencode-exporter/1.1.0"
    exporter_server_url = None
    exporter_auth_file = None

    def do_GET(self):
        if self.path != "/metrics":
            self.send_error(404)
            return
        try:
            body = collect(self.exporter_server_url, self.exporter_auth_file).encode()
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
    parser.add_argument(
        "--auth-file",
        default=default_auth_path(),
        metavar="PATH",
        help="OpenCode auth file used for subscription quota collection "
        "(default: %(default)s)",
    )
    args = parser.parse_args()

    handler = MetricsHandler
    handler.exporter_server_url = args.server_url.rstrip("/")
    handler.exporter_auth_file = args.auth_file
    server = ThreadingHTTPServer(args.bind, handler)
    host, port = args.bind
    print(f"serving metrics on http://{host}:{port}/metrics", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
