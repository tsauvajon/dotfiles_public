#!/usr/bin/env python3
"""Prometheus exporter for an OpenCode shared server.

Polls the HTTP API of an `opencode serve` instance (health, projects and
per-directory session lists) and exposes aggregate gauges in the Prometheus
text exposition format. Standard library only.

Per-agent token and cost metrics are attributed from assistant message
info records, because a session summary only records the currently
selected agent, which would misattribute historical usage. When a local
OpenCode SQLite database (--db, default under the XDG data home) is
available it is opened read-only and the usage is aggregated with a
single indexed query; only sessions the database does not cover fall
back to the per-session message API (/session/{id}/message), so remote
or custom servers keep working. Token and session-count metrics keep using
session summaries; cost metrics prefer message-level data.

The exporter also collects subscription quota state (ai_subscription_quota_*)
by querying each provider's usage endpoint directly, using the credentials
from the local OpenCode auth file. It never refreshes OAuth tokens itself;
when an access token is stale the affected subscription reports
ai_subscription_quota_up 0 until the OpenCode server refreshes it.

The exporter answers /metrics even while the OpenCode server is down by
reporting opencode_up 0, and provides a lightweight /health endpoint for
service liveness checks.
"""

import argparse
import json
import math
import os
import sqlite3
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

# OpenCode model provider IDs (model.providerID) that need normalizing to the
# canonical provider labels above; every other provider ID passes through
# unchanged.
MODEL_PROVIDER_LABELS = {"zai-coding-plan": "zai"}


def model_provider_label(provider_id):
    return MODEL_PROVIDER_LABELS.get(provider_id, provider_id)


class ServerError(Exception):
    pass


class QuotaError(Exception):
    pass


class PricingError(Exception):
    pass


def _pricing_number(value, location):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise PricingError(f"{location} must be a number")
    number = float(value)
    if not math.isfinite(number) or number < 0:
        raise PricingError(f"{location} must be finite and nonnegative")
    return number


def _pricing_tier(value, location):
    if not isinstance(value, dict):
        raise PricingError(f"{location} must be an object")
    fields = ("input", "output", "cache_read", "cache_write")
    missing = [field for field in fields if field not in value]
    if missing:
        raise PricingError(f"{location} is missing {', '.join(missing)}")
    return {
        field: _pricing_number(value[field], f"{location}.{field}")
        for field in fields
    }


def load_pricing_file(path):
    """Load validated OpenCode provider/model cost entries from PATH."""
    if not path:
        return {}
    try:
        with open(path, encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        raise PricingError(f"cannot read {path}: {error}") from error
    if not isinstance(document, dict) or not isinstance(document.get("provider"), dict):
        raise PricingError("root.provider must be an object")

    pricing = {}
    for provider_id, provider in document["provider"].items():
        location = f"provider.{provider_id}"
        if not isinstance(provider, dict) or not isinstance(provider.get("models"), dict):
            raise PricingError(f"{location}.models must be an object")
        for model_id, model in provider["models"].items():
            model_location = f"{location}.models.{model_id}"
            if not isinstance(model, dict) or "cost" not in model:
                raise PricingError(f"{model_location}.cost must be an object")
            cost = model["cost"]
            rates = _pricing_tier(cost, f"{model_location}.cost")
            if "context_over_200k" in cost:
                rates["context_over_200k"] = _pricing_tier(
                    cost["context_over_200k"],
                    f"{model_location}.cost.context_over_200k",
                )
            pricing[(str(provider_id), str(model_id))] = rates
    return pricing


def positive_finite_cost(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    number = float(value)
    return number if math.isfinite(number) and number > 0 else None


def priced_usage(
    provider_id,
    model_id,
    tokens,
    reported_cost,
    pricing,
    context_over_200k=None,
):
    """Return (cost, estimated subtotal, missing-pricing flag)."""
    reported = positive_finite_cost(reported_cost)
    if reported is not None:
        return reported, 0.0, False
    usage = sum(tokens.get(token_type, 0) for token_type in TOKEN_TYPES)
    rates = pricing.get((provider_id, model_id))
    if rates is None:
        return 0.0, 0.0, usage > 0
    if context_over_200k is None:
        context_over_200k = (
            tokens.get("input", 0)
            + tokens.get("cache_read", 0)
            + tokens.get("cache_write", 0)
            > 200000
        )
    if context_over_200k:
        rates = rates.get("context_over_200k", rates)
    estimate = (
        tokens.get("input", 0) * rates["input"]
        + (tokens.get("output", 0) + tokens.get("reasoning", 0)) * rates["output"]
        + tokens.get("cache_read", 0) * rates["cache_read"]
        + tokens.get("cache_write", 0) * rates["cache_write"]
    ) / 1_000_000
    return estimate, estimate, False


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


def agent_token_samples(values):
    return [
        (
            [
                ("agent", agent),
                ("model", model_id),
                ("provider", provider),
                ("type", token_type),
            ],
            values[(agent, provider, model_id)][token_type],
        )
        for agent, provider, model_id in sorted(values)
        for token_type in TOKEN_TYPES
    ]


AGENT_SESSION_STATS = (("p10", 0.10), ("p50", 0.50), ("p90", 0.90), ("mean", None))


def quantile(sorted_values, fraction):
    """Linearly interpolated quantile over an ascending list, matching
    Prometheus's quantile semantics; returns 0 for an empty list."""
    if not sorted_values:
        return 0.0
    rank = fraction * (len(sorted_values) - 1)
    lower = int(rank)
    upper = min(lower + 1, len(sorted_values) - 1)
    weight = rank - lower
    return sorted_values[lower] * (1.0 - weight) + sorted_values[upper] * weight


def agent_session_token_samples(values):
    """Render per-session token distribution gauges: for every observed
    (agent, provider, model) and token type, p10/p50/p90/mean over the
    per-session totals seen in stored sessions."""
    samples = []
    for agent, provider, model_id in sorted(values):
        for token_type in TOKEN_TYPES:
            per_session = sorted(values[(agent, provider, model_id)][token_type])
            for stat, fraction in AGENT_SESSION_STATS:
                if fraction is None:
                    value = sum(per_session) / len(per_session) if per_session else 0.0
                else:
                    value = quantile(per_session, fraction)
                samples.append(
                    (
                        [
                            ("agent", agent),
                            ("model", model_id),
                            ("provider", provider),
                            ("type", token_type),
                            ("stat", stat),
                        ],
                        round(value, 6),
                    )
                )
    return samples


def usage_tokens(tokens):
    """Normalize a usage object ({input, output, reasoning, cache: {read,
    write}}) into per-token-type counts; missing fields count as zero."""
    if not isinstance(tokens, dict):
        tokens = {}
    cache = tokens.get("cache")
    if not isinstance(cache, dict):
        cache = {}
    return {
        "input": int(tokens.get("input") or 0),
        "output": int(tokens.get("output") or 0),
        "reasoning": int(tokens.get("reasoning") or 0),
        "cache_read": int(cache.get("read") or 0),
        "cache_write": int(cache.get("write") or 0),
    }


def message_usage_from_db(db_path, session_agents):
    """Return grouped assistant-message usage and covered session IDs.

    The single query groups by session, agent, provider/model, reported-cost
    status, and OpenCode's >200k request tier. Python applies configured rates
    to these compact groups rather than loading raw message JSON rows.
    """
    session_ids = sorted(session_agents)
    if not session_ids:
        return [], set()
    uri = f"file:{quote(os.path.abspath(db_path))}?mode=ro"
    connection = sqlite3.connect(uri, uri=True)
    try:
        placeholders = ",".join("?" * len(session_ids))
        cursor = connection.execute(
            f"""
            SELECT s.id,
                   COALESCE(NULLIF(json_extract(m.data, '$.agent'), ''), '') AS message_agent,
                   COALESCE(NULLIF(json_extract(m.data, '$.providerID'), ''), 'unknown') AS provider_id,
                   COALESCE(NULLIF(json_extract(m.data, '$.modelID'), ''), 'unknown') AS model_id,
                   CASE WHEN typeof(json_extract(m.data, '$.cost')) IN ('integer', 'real')
                              AND json_extract(m.data, '$.cost') > 0
                        THEN 1 ELSE 0 END AS has_reported_cost,
                   CASE WHEN COALESCE(json_extract(m.data, '$.tokens.input'), 0)
                                  + COALESCE(json_extract(m.data, '$.tokens.cache.read'), 0)
                                  + COALESCE(json_extract(m.data, '$.tokens.cache.write'), 0) > 200000
                         THEN 1 ELSE 0 END AS context_over_200k,
                   COUNT(m.id) AS assistant_messages,
                   SUM(COALESCE(json_extract(m.data, '$.tokens.input'), 0)),
                   SUM(COALESCE(json_extract(m.data, '$.tokens.output'), 0)),
                   SUM(COALESCE(json_extract(m.data, '$.tokens.reasoning'), 0)),
                   SUM(COALESCE(json_extract(m.data, '$.tokens.cache.read'), 0)),
                   SUM(COALESCE(json_extract(m.data, '$.tokens.cache.write'), 0)),
                   SUM(CASE WHEN typeof(json_extract(m.data, '$.cost')) IN ('integer', 'real')
                                  AND json_extract(m.data, '$.cost') > 0
                            THEN json_extract(m.data, '$.cost') ELSE 0 END)
            FROM session s
            LEFT JOIN message m
              ON m.session_id = s.id
             AND json_extract(m.data, '$.role') = 'assistant'
            WHERE s.id IN ({placeholders})
            GROUP BY s.id, message_agent, provider_id, model_id,
                     has_reported_cost, context_over_200k
            """,
            session_ids,
        )
        covered = set()
        groups = []
        for row in cursor:
            (
                session_id,
                message_agent,
                provider_id,
                model_id,
                has_reported_cost,
                _context_over_200k,
                assistant_messages,
                *totals,
            ) = row
            covered.add(session_id)
            if not assistant_messages:
                # Session with no assistant messages: covered, but it must
                # not mint a zero-valued series for its agent.
                continue
            groups.append(
                {
                    "session_id": str(session_id),
                    "agent": str(message_agent or session_agents.get(session_id) or "unknown"),
                    "provider": str(provider_id),
                    "model": str(model_id),
                    "tokens": {
                        token_type: int(total or 0)
                        for token_type, total in zip(TOKEN_TYPES, totals[:-1])
                    },
                    "reported_cost": float(totals[-1] or 0.0) if has_reported_cost else 0.0,
                    "context_over_200k": bool(_context_over_200k),
                }
            )
        return groups, covered
    finally:
        connection.close()


def xdg_data_home():
    return os.environ.get("XDG_DATA_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "share"
    )


def default_auth_path():
    return os.path.join(xdg_data_home(), "opencode", "auth.json")


def default_db_path():
    return os.path.join(xdg_data_home(), "opencode", "opencode-stable.db")


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
        if existing is not None:
            if existing["limit_credits"] is None and credits:
                # CREDIT_LIMIT still wins for quota and credit values, but
                # keep the reset timestamp of the entry it replaces when the
                # credit entry itself has no valid reset.
                if window["reset_seconds"] <= 0.0:
                    window["reset_seconds"] = existing["reset_seconds"]
                windows_by_label[window["window"]] = window
            elif existing["reset_seconds"] <= 0.0 and window["reset_seconds"] > 0.0:
                # The kept entry lacks a valid reset timestamp; a duplicate
                # entry for the same window can still supply one.
                existing["reset_seconds"] = window["reset_seconds"]
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


def collect(server_url, auth_path, db_path=None, pricing=None):
    started = time.monotonic()

    health = fetch_json(server_url, "/global/health")
    if not isinstance(health, dict) or not health.get("healthy"):
        raise ServerError(f"/global/health did not report healthy: {health!r}")

    projects, sessions = collect_sessions(server_url)

    token_totals = {token_type: 0 for token_type in TOKEN_TYPES}
    pricing = pricing or {}
    model_cost = {}
    model_estimated_cost = {}
    pricing_missing = {}
    model_sessions = {}
    model_tokens = {}
    agent_tokens = {}
    agent_cost = {}
    session_agent_tokens = {}
    cost_total = 0.0
    lines_added_total = 0
    lines_deleted_total = 0
    last_update_seconds = 0.0
    active_24h = 0
    now_ms = time.time() * 1000.0

    # Per-agent attribution cannot use session.agent: it only records the
    # currently selected agent and would misattribute historical usage.
    # Aggregate assistant message info records instead (token data
    # duplicated in message parts such as step-finish is ignored), with
    # each message's agent falling back to the session agent, then
    # "unknown". The local OpenCode SQLite database answers this with one
    # read-only query per scrape; the per-session message API stays as the
    # fallback for sessions it does not cover, so remote or custom servers
    # keep working.
    session_agents = {
        str(session.get("id")): str(session.get("agent") or "")
        for session in sessions
        if session.get("id")
    }
    usage_groups = []
    db_covered = set()
    if db_path:
        try:
            usage_groups, db_covered = message_usage_from_db(
                db_path, session_agents
            )
        except (OSError, ValueError, sqlite3.Error) as error:
            # An unavailable or stale database must not fail the scrape:
            # every session falls back to the message API below and the
            # session-summary metrics remain unaffected.
            print(
                f"opencode database unusable, using message API fallback: {error}",
                file=sys.stderr,
            )
    sessions_with_usage = {usage["session_id"] for usage in usage_groups}

    for session in sessions:
        # Token/session families stay based on the session summaries.
        model = session.get("model") or {}
        model_key = (
            model_provider_label(str(model.get("providerID") or "unknown")),
            str(model.get("id") or "unknown"),
        )
        model_tokens.setdefault(model_key, {token_type: 0 for token_type in TOKEN_TYPES})
        session_tokens = usage_tokens(session.get("tokens"))
        for token_type, value in session_tokens.items():
            token_totals[token_type] += value
            model_tokens[model_key][token_type] += value

        model_cost.setdefault(model_key, 0.0)
        model_sessions[model_key] = model_sessions.get(model_key, 0) + 1

        # Per-agent attribution comes from the database aggregate above for
        # covered sessions; the message API only serves the rest.
        session_agent = str(session.get("agent") or "unknown")
        session_id = str(session.get("id") or "")
        messages_obtained = session_id in sessions_with_usage
        if session_id and session_id not in db_covered:
            try:
                messages = fetch_json(
                    server_url,
                    f"/session/{quote(session_id, safe='')}/message",
                )
            except ServerError:
                messages = None
            if isinstance(messages, list):
                for envelope in messages:
                    info = envelope.get("info") if isinstance(envelope, dict) else None
                    if (
                        not isinstance(info, dict)
                        or str(info.get("role") or "") != "assistant"
                    ):
                        continue
                    messages_obtained = True
                    agent = str(info.get("agent") or session_agent)
                    usage_groups.append(
                        {
                            "session_id": session_id,
                            "agent": agent,
                            "provider": str(info.get("providerID") or "unknown"),
                            "model": str(info.get("modelID") or "unknown"),
                            "tokens": usage_tokens(info.get("tokens")),
                            "reported_cost": info.get("cost"),
                        }
                    )

        if not messages_obtained:
            # Session summaries are a last resort only when assistant message
            # info cannot be obtained from either SQLite or the API.
            usage_groups.append(
                {
                    "session_id": session_id,
                    "agent": session_agent,
                    "provider": str(model.get("providerID") or "unknown"),
                    "model": str(model.get("id") or "unknown"),
                    "tokens": session_tokens,
                    "reported_cost": session.get("cost"),
                    "attribute_agent_tokens": False,
                    # A session aggregate cannot establish whether any single
                    # assistant request crossed the pricing tier threshold.
                    "context_over_200k": False,
                }
            )

        summary = session.get("summary") or {}
        lines_added_total += int(summary.get("additions") or 0)
        lines_deleted_total += int(summary.get("deletions") or 0)

        updated_ms = float((session.get("time") or {}).get("updated") or 0.0)
        last_update_seconds = max(last_update_seconds, updated_ms / 1000.0)
        if updated_ms > 0 and now_ms - updated_ms <= ACTIVE_WINDOW_SECONDS * 1000.0:
            active_24h += 1

    if not pricing:
        # Without configured rates, positive message costs retain their agent
        # attribution while the session summary supplies any unreported
        # remainder. This keeps the production/default cost counters from
        # regressing when zero-cost message records are present.
        attributed_by_session = {}
        for usage in usage_groups:
            attributed_by_session[usage["session_id"]] = (
                attributed_by_session.get(usage["session_id"], 0.0)
                + (positive_finite_cost(usage["reported_cost"]) or 0.0)
            )
        for session in sessions:
            session_id = str(session.get("id") or "")
            summary_cost = positive_finite_cost(session.get("cost")) or 0.0
            remainder = summary_cost - attributed_by_session.get(session_id, 0.0)
            if remainder <= 0:
                continue
            model = session.get("model") or {}
            usage_groups.append(
                {
                    "session_id": session_id,
                    "agent": str(session.get("agent") or "unknown"),
                    "provider": str(model.get("providerID") or "unknown"),
                    "model": str(model.get("id") or "unknown"),
                    "tokens": {token_type: 0 for token_type in TOKEN_TYPES},
                    "reported_cost": remainder,
                    "attribute_agent_tokens": False,
                }
            )

    # Database and API groups share one pricing and attribution path. A
    # summary remainder may supplement, but never duplicate, message costs.
    for usage in usage_groups:
        agent = usage["agent"]
        tokens = usage["tokens"]
        raw_provider = usage["provider"]
        model_id = usage["model"]
        model_key = (model_provider_label(raw_provider), model_id)
        if usage.get("attribute_agent_tokens", True):
            agent_key = (agent, *model_key)
            bucket = agent_tokens.setdefault(
                agent_key, {token_type: 0 for token_type in TOKEN_TYPES}
            )
            session_bucket = session_agent_tokens.setdefault(usage["session_id"], {})
            per_session = session_bucket.setdefault(
                agent_key, {token_type: 0 for token_type in TOKEN_TYPES}
            )
            for token_type, value in tokens.items():
                bucket[token_type] += value
                per_session[token_type] += value
        cost, estimated, missing = priced_usage(
            raw_provider,
            model_id,
            tokens,
            usage["reported_cost"],
            pricing,
            usage.get("context_over_200k"),
        )
        # Pricing lookup uses the raw OpenCode provider ID above. Only the
        # emitted metric label is normalized for dashboard joins.
        pricing_missing.setdefault(model_key, False)
        cost_total += cost
        model_cost[model_key] = model_cost.get(model_key, 0.0) + cost
        agent_cost[agent] = agent_cost.get(agent, 0.0) + cost
        if estimated > 0:
            model_estimated_cost[model_key] = (
                model_estimated_cost.get(model_key, 0.0) + estimated
            )
        if missing:
            pricing_missing[model_key] = True

    # Per-session statistics: one sample per observed token type per
    # (agent, provider, model), over the sessions in which that tuple appeared.
    agent_session_stats = {}
    for session_tokens in session_agent_tokens.values():
        for key, types in session_tokens.items():
            entry = agent_session_stats.setdefault(
                key, {token_type: [] for token_type in TOKEN_TYPES}
            )
            for token_type, value in types.items():
                entry[token_type].append(value)

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
            "opencode_agent_tokens_total",
            "Cumulative tokens per agent, provider/model and token type, summed from assistant message info records.",
            "counter",
            agent_token_samples(agent_tokens),
        ),
        format_metric(
            "opencode_agent_session_tokens",
            "Token distribution per agent, provider/model and token type over per-session totals (stat label: p10, p50, p90, mean); gauge, not a counter.",
            "gauge",
            agent_session_token_samples(agent_session_stats),
        ),
        format_metric(
            "opencode_session_cost_usd_total",
            "Cumulative session cost in USD from reported costs plus pricing fallback estimates.",
            "counter",
            [([], round(cost_total, 6))],
        ),
        format_metric(
            "opencode_model_cost_usd_total",
            "Cumulative cost in USD per provider/model from reported costs plus pricing fallback estimates.",
            "counter",
            model_samples(model_cost, lambda value: round(value, 6)),
        ),
        format_metric(
            "opencode_agent_cost_usd_total",
            "Cumulative cost in USD per agent from reported costs plus pricing fallback estimates.",
            "counter",
            [
                ([("agent", agent)], round(agent_cost[agent], 6))
                for agent in sorted(agent_cost)
            ],
        ),
        format_metric(
            "opencode_model_estimated_cost_usd_total",
            "Cumulative provider/model cost subtotal supplied by pricing fallback estimates.",
            "counter",
            model_samples(model_estimated_cost, lambda value: round(value, 6)),
        ),
        format_metric(
            "opencode_pricing_missing",
            "1 when nonzero usage has no pricing entry and no positive persisted cost.",
            "gauge",
            model_samples(pricing_missing, int),
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
    server_version = "opencode-exporter/1.4.0"
    exporter_server_url = None
    exporter_auth_file = None
    exporter_db_file = None
    exporter_pricing = {}

    def do_GET(self):
        if self.path == "/health":
            body = b"OK\n"
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if self.path != "/metrics":
            self.send_error(404)
            return
        try:
            body = collect(
                self.exporter_server_url,
                self.exporter_auth_file,
                self.exporter_db_file,
                self.exporter_pricing,
            ).encode()
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
    parser.add_argument(
        "--db",
        default=default_db_path(),
        metavar="PATH",
        help="OpenCode SQLite database (opencode-stable.db) opened read-only "
        "to aggregate per-agent token/cost usage in one query; sessions it "
        "does not cover fall back to the message API. Pass an empty path to "
        "always use the API (default: %(default)s)",
    )
    parser.add_argument(
        "--pricing-file",
        default="",
        metavar="PATH",
        help="OpenCode-shaped JSON model pricing file (default: disabled)",
    )
    args = parser.parse_args()

    try:
        pricing = load_pricing_file(args.pricing_file)
    except PricingError as error:
        parser.error(f"invalid pricing file: {error}")

    handler = MetricsHandler
    handler.exporter_server_url = args.server_url.rstrip("/")
    handler.exporter_auth_file = args.auth_file
    handler.exporter_db_file = args.db
    handler.exporter_pricing = pricing
    server = ThreadingHTTPServer(args.bind, handler)
    host, port = args.bind
    print(f"serving metrics on http://{host}:{port}/metrics", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
