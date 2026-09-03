{ pkgs, lib }:

let
  src = ./.;
in
pkgs.runCommand "opencode-exporter-test"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    inherit src;
  }
  ''
    export NIX_TEST_SRC="$src"

    python3 <<'PYEOF'
    import importlib.util
    import json
    import os
    import sqlite3
    import sys
    import tempfile

    module_path = os.path.join(os.environ["NIX_TEST_SRC"], "opencode-exporter.py")
    spec = importlib.util.spec_from_file_location("opencode_exporter", module_path)
    exporter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(exporter)

    failures = []

    def check(name, actual, expected):
        if actual != expected:
            failures.append(f"{name}: expected {expected!r}, got {actual!r}")

    def check_close(name, actual, expected, tolerance=1e-9):
        if abs(actual - expected) > tolerance:
            failures.append(f"{name}: expected {expected!r}, got {actual!r}")

    def check_raises(name, func):
        try:
            func()
        except exporter.QuotaError:
            return
        except Exception as error:
            failures.append(f"{name}: raised {type(error).__name__} instead of QuotaError")
            return
        failures.append(f"{name}: did not raise QuotaError")

    check("clamp01 below", exporter.clamp01(-1.0), 0.0)
    check("clamp01 middle", exporter.clamp01(0.5), 0.5)
    check("clamp01 above", exporter.clamp01(2.0), 1.0)

    check("window 5h", exporter.window_label_from_seconds(18000), "5h")
    check("window 1d", exporter.window_label_from_seconds(86400), "1d")
    check("window 1w", exporter.window_label_from_seconds(604800), "1w")
    check("window 1mo", exporter.window_label_from_seconds(2592000), "1mo")
    check("window 2d generic", exporter.window_label_from_seconds(172800), "2d")
    check("window zero", exporter.window_label_from_seconds(0), "unknown")
    check("window seconds", exporter.window_label_from_seconds(1234), "1234s")

    check("zai 5 hours", exporter.zai_window_label({"unit": 3, "number": 5}), "5h")
    check("zai 1 month", exporter.zai_window_label({"unit": 5, "number": 1}), "1mo")
    check("zai 1 week", exporter.zai_window_label({"unit": 6, "number": 1}), "1w")
    check("zai tokens fallback", exporter.zai_window_label({"type": "TOKENS_LIMIT"}), "5h")
    check("zai time fallback", exporter.zai_window_label({"type": "TIME_LIMIT"}), "1mo")
    check("zai unknown", exporter.zai_window_label({}), "unknown")

    check("model provider zai mapping", exporter.model_provider_label("zai-coding-plan"), "zai")
    check("model provider openai passthrough", exporter.model_provider_label("openai"), "openai")
    check("model provider unknown passthrough", exporter.model_provider_label("anthropic"), "anthropic")

    plan, windows = exporter.parse_openai_usage(
        {
            "plan_type": "plus",
            "rate_limit": {
                "primary_window": {
                    "used_percent": 78,
                    "limit_window_seconds": 18000,
                    "reset_at": 1788179730,
                },
                "secondary_window": {
                    "used_percent": 12,
                    "limit_window_seconds": 604800,
                    "reset_at": 1788766530,
                },
            },
        }
    )
    check("openai plan", plan, "plus")
    check("openai window count", len(windows), 2)
    by_label = {window["window"]: window for window in windows}
    five_hour = by_label["5h"]
    weekly = by_label["1w"]
    check("openai 5h label", five_hour["window"], "5h")
    check_close("openai 5h used", five_hour["used_ratio"], 0.78)
    check_close("openai 5h remaining", five_hour["remaining_ratio"], 0.22)
    check("openai 5h reset", five_hour["reset_seconds"], 1788179730.0)
    check("openai 5h no credits", five_hour["limit_credits"], None)
    check("openai 1w label", weekly["window"], "1w")
    check_close("openai 1w used", weekly["used_ratio"], 0.12)
    check("openai windows sorted", [w["window"] for w in windows], ["1w", "5h"])

    plan, windows = exporter.parse_zai_quota(
        {
            "data": {
                "level": "lite",
                "limits": [
                    {
                        "type": "CREDIT_LIMIT",
                        "unit": 3,
                        "number": 5,
                        "usage": 2000,
                        "currentValue": 522,
                        "remaining": 1477,
                        "percentage": 26,
                        "nextResetTime": 1788186091775,
                    },
                    {
                        "type": "CREDIT_LIMIT",
                        "unit": 6,
                        "number": 1,
                        "usage": 10000,
                        "currentValue": 522,
                        "remaining": 9477,
                        "percentage": 5,
                        "nextResetTime": 1788769081975,
                    },
                    {
                        "type": "TOKENS_LIMIT",
                        "percentage": 40,
                        "nextResetTime": 1788186091000,
                    },
                ],
            }
        }
    )
    check("zai plan", plan, "lite")
    check("zai window count", len(windows), 2)
    by_window = {window["window"]: window for window in windows}
    five = by_window["5h"]
    weekly = by_window["1w"]
    check_close("zai 5h used", five["used_ratio"], 522 / 2000)
    check_close("zai 5h remaining", five["remaining_ratio"], 1477 / 2000)
    check("zai 5h limit credits", five["limit_credits"], 2000.0)
    check("zai 5h used credits", five["used_credits"], 522.0)
    check("zai 5h reset", five["reset_seconds"], 1788186091.775)
    check_close("zai 1w used", weekly["used_ratio"], 522 / 10000)
    check_close("zai 1w remaining", weekly["remaining_ratio"], 9477 / 10000)
    check("zai 1w limit credits", weekly["limit_credits"], 10000.0)

    plan, windows = exporter.parse_zai_quota(
        {
            "data": {
                "level": "lite",
                "limits": [
                    {
                        "type": "TOKENS_LIMIT",
                        "percentage": 40,
                        "nextResetTime": 1788186091000,
                    },
                    {
                        "type": "CREDIT_LIMIT",
                        "unit": 3,
                        "number": 5,
                        "usage": 2000,
                        "currentValue": 522,
                        "remaining": 1477,
                        "percentage": 26,
                        "nextResetTime": 1788186091775,
                    },
                ],
            }
        }
    )
    check("zai collision keeps one window", len(windows), 1)
    check(
        "zai collision prefers credits",
        windows[0]["limit_credits"],
        2000.0,
    )
    check(
        "zai collision keeps credit reset",
        windows[0]["reset_seconds"],
        1788186091.775,
    )

    # Regression: a same-window TOKENS_LIMIT entry with a valid reset must
    # lend its reset timestamp to the preferred CREDIT_LIMIT entry when the
    # credit entry itself reports no reset (e.g. right after a window reset).
    plan, windows = exporter.parse_zai_quota(
        {
            "data": {
                "level": "lite",
                "limits": [
                    {
                        "type": "TOKENS_LIMIT",
                        "percentage": 40,
                        "nextResetTime": 1788186091000,
                    },
                    {
                        "type": "CREDIT_LIMIT",
                        "unit": 3,
                        "number": 5,
                        "usage": 2000,
                        "currentValue": 522,
                        "remaining": 1477,
                        "percentage": 26,
                        "nextResetTime": 0,
                    },
                ],
            }
        }
    )
    check("zai missing credit reset keeps one window", len(windows), 1)
    check(
        "zai missing credit reset prefers credits",
        windows[0]["limit_credits"],
        2000.0,
    )
    check(
        "zai missing credit reset keeps tokens reset",
        windows[0]["reset_seconds"],
        1788186091.0,
    )

    # Same collision with the entries in the opposite order.
    plan, windows = exporter.parse_zai_quota(
        {
            "data": {
                "level": "lite",
                "limits": [
                    {
                        "type": "CREDIT_LIMIT",
                        "unit": 3,
                        "number": 5,
                        "usage": 2000,
                        "currentValue": 522,
                        "remaining": 1477,
                        "percentage": 26,
                    },
                    {
                        "type": "TOKENS_LIMIT",
                        "percentage": 40,
                        "nextResetTime": 1788186091000,
                    },
                ],
            }
        }
    )
    check("zai credit-first collision keeps one window", len(windows), 1)
    check(
        "zai credit-first collision prefers credits",
        windows[0]["limit_credits"],
        2000.0,
    )
    check(
        "zai credit-first collision keeps tokens reset",
        windows[0]["reset_seconds"],
        1788186091.0,
    )

    # When every duplicate entry lacks a reset timestamp, none may be invented.
    plan, windows = exporter.parse_zai_quota(
        {
            "data": {
                "level": "lite",
                "limits": [
                    {
                        "type": "TOKENS_LIMIT",
                        "percentage": 40,
                    },
                    {
                        "type": "CREDIT_LIMIT",
                        "unit": 3,
                        "number": 5,
                        "usage": 2000,
                        "currentValue": 522,
                        "remaining": 1477,
                        "percentage": 26,
                        "nextResetTime": 0,
                    },
                ],
            }
        }
    )
    check("zai all-missing resets keeps one window", len(windows), 1)
    check(
        "zai all-missing resets invents nothing",
        windows[0]["reset_seconds"],
        0.0,
    )

    check_raises("openai empty payload", lambda: exporter.parse_openai_usage({}))
    check_raises(
        "openai missing rate limit",
        lambda: exporter.parse_openai_usage({"plan_type": "plus"}),
    )
    check_raises("zai empty payload", lambda: exporter.parse_zai_quota({}))
    check_raises("zai no limits", lambda: exporter.parse_zai_quota({"data": {}}))

    entry = {
        "type": "oauth",
        "access": "token",
        "accountId": "account",
        "expires": 1,
    }
    check_raises(
        "openai stale token",
        lambda: exporter.collect_openai_quota(entry, 10**13),
    )
    check_raises(
        "openai wrong auth type",
        lambda: exporter.collect_openai_quota({"type": "api"}, 0),
    )
    check_raises("zai missing key", lambda: exporter.collect_zai_quota({}))

    exporter.quota_cache.clear()
    exporter.quota_cache.update(
        {
            "openai": {
                "fetched_monotonic": 0.0,
                "plan": "plus",
                "windows": [
                    {
                        "window": "5h",
                        "used_ratio": 0.78,
                        "remaining_ratio": 0.22,
                        "reset_seconds": 1788179730.0,
                        "limit_credits": None,
                        "used_credits": None,
                    }
                ],
                "error": None,
                "success_wall": 100.0,
            },
            "zai-coding-plan": {
                "fetched_monotonic": 0.0,
                "plan": "lite",
                "windows": [
                    {
                        "window": "5h",
                        "used_ratio": 0.26,
                        "remaining_ratio": 0.74,
                        "reset_seconds": 1788186091.775,
                        "limit_credits": 2000.0,
                        "used_credits": 522.0,
                    }
                ],
                "error": None,
                "success_wall": 200.0,
            },
        }
    )
    exposition = "\n".join(
        line for family in exporter.quota_families() for line in family
    )
    quota_samples = [
        line for line in exposition.splitlines() if line.startswith("ai_subscription_")
    ]
    check(
        "quota openai up labels",
        'ai_subscription_quota_up{subscription="openai",provider="openai",} 1.0'
        in quota_samples,
        True,
    )
    check(
        "quota zai up labels",
        'ai_subscription_quota_up{subscription="zai-coding-plan",provider="zai",} 1.0'
        in quota_samples,
        True,
    )
    check(
        "quota openai info labels",
        'ai_subscription_info{subscription="openai",provider="openai",plan="plus",} 1.0'
        in quota_samples,
        True,
    )
    check(
        "quota zai info labels",
        'ai_subscription_info{subscription="zai-coding-plan",provider="zai",plan="lite",} 1.0'
        in quota_samples,
        True,
    )
    check(
        "quota openai window labels",
        'ai_subscription_quota_used_ratio{subscription="openai",provider="openai",window="5h",} 0.78'
        in quota_samples,
        True,
    )
    check(
        "quota zai window labels",
        'ai_subscription_quota_used_ratio{subscription="zai-coding-plan",provider="zai",window="5h",} 0.26'
        in quota_samples,
        True,
    )
    check(
        "quota zai credits labels",
        'ai_subscription_quota_limit_credits{subscription="zai-coding-plan",provider="zai",window="5h",} 2000.0'
        in quota_samples,
        True,
    )
    check(
        "quota openai last scrape labels",
        'ai_subscription_quota_last_scrape_timestamp_seconds{subscription="openai",provider="openai",} 100.0'
        in quota_samples,
        True,
    )
    check(
        "every quota sample carries provider",
        all("provider=" in line for line in quota_samples),
        True,
    )
    check(
        "every quota sample keeps subscription",
        all("subscription=" in line for line in quota_samples),
        True,
    )

    # XDG defaults for the auth file and the exporter database.
    original_xdg = os.environ.get("XDG_DATA_HOME")
    os.environ["XDG_DATA_HOME"] = "/tmp/opencode-exporter-test-data"
    try:
        check(
            "default db path follows xdg",
            exporter.default_db_path(),
            "/tmp/opencode-exporter-test-data/opencode/opencode-stable.db",
        )
        check(
            "default auth path follows xdg",
            exporter.default_auth_path(),
            "/tmp/opencode-exporter-test-data/opencode/auth.json",
        )
    finally:
        if original_xdg is None:
            os.environ.pop("XDG_DATA_HOME", None)
        else:
            os.environ["XDG_DATA_HOME"] = original_xdg

    # collect() end-to-end with mocked API payloads: per-agent token/cost
    # attribution comes from assistant message info records, because
    # session.agent is only the latest selected agent. A message's agent
    # falls back to the session agent, then "unknown"; token data duplicated
    # in parts (step-finish) and non-assistant messages are ignored.
    # Session- and model-level families keep using the session summaries
    # below. The local SQLite database (opencode-stable.db) answers covered
    # sessions in one read-only query; the message API only serves sessions
    # the database does not cover.
    agent_sessions = [
        {
            "id": "s1",
            "agent": "build",
            "cost": 0.5,
            "tokens": {
                "input": 10,
                "output": 20,
                "reasoning": 1,
                "cache": {"read": 2, "write": 3},
            },
            "model": {"providerID": "openai", "id": "gpt-5"},
            "time": {"updated": 1000.0},
        },
        {
            "id": "s2",
            "agent": "plan",
            "cost": 0.25,
            "tokens": {"input": 5, "output": 6, "cache": {"read": 7, "write": 8}},
            "model": {"providerID": "zai-coding-plan", "id": "glm"},
            "time": {"updated": 2000.0},
        },
        {
            "id": "s3",
            "cost": 0.25,
            "tokens": {"output": 4, "cache": {"write": 9}},
            "time": {"updated": 3000.0},
        },
        {
            "id": "s4",
            "agent": "",
            "cost": 0.25,
            "tokens": {"input": 1},
            "time": {"updated": 4000.0},
        },
    ]

    # Expected attribution from these envelopes:
    #   build:   input 10, output 27, reasoning 1, cache_read 2,
    #            cache_write 3, cost 0.35  (m1 + m3; step-finish and user
    #            message data ignored)
    #   plan:    input 105, output 6, reasoning 0, cache_read 7,
    #            cache_write 8, cost 0.40  (s1 m2 + s2 m1: one session can
    #            feed several agents, one agent can span sessions)
    #   unknown: input 1, output 4, cache_write 9, cost 0.25  (s3: no
    #            message agent and no session agent; s4 has no messages and
    #            contributes nothing)
    session_messages = {
        "s1": [
            {
                "info": {
                    "role": "assistant",
                    "agent": "build",
                    "cost": 0.3,
                    "tokens": {
                        "input": 10,
                        "output": 20,
                        "reasoning": 1,
                        "cache": {"read": 2, "write": 3},
                    },
                },
                "parts": [
                    {
                        "type": "step-finish",
                        "cost": 999,
                        "tokens": {"input": 999, "output": 999},
                    }
                ],
            },
            {
                "info": {
                    "role": "assistant",
                    "agent": "plan",
                    "cost": 0.15,
                    "tokens": {"input": 100},
                },
                "parts": [],
            },
            {
                "info": {
                    "role": "assistant",
                    "cost": 0.05,
                    "tokens": {"output": 7},
                },
                "parts": [],
            },
            {
                "info": {
                    "role": "user",
                    "agent": "build",
                    "cost": 5,
                    "tokens": {"input": 55},
                },
                "parts": [],
            },
        ],
        "s2": [
            {
                "info": {
                    "role": "assistant",
                    "cost": 0.25,
                    "tokens": {
                        "input": 5,
                        "output": 6,
                        "cache": {"read": 7, "write": 8},
                    },
                },
                "parts": [],
            }
        ],
        "s3": [
            {
                "info": {
                    "role": "assistant",
                    "cost": 0.2,
                    "tokens": {"output": 4, "cache": {"write": 9}},
                },
                "parts": [],
            },
            {
                "info": {
                    "role": "assistant",
                    "agent": "",
                    "cost": 0.05,
                    "tokens": {"input": 1},
                },
                "parts": [],
            },
        ],
        "s4": [],
    }

    message_api_calls = []

    def fake_fetch_json(server_url, path):
        if path == "/global/health":
            return {"healthy": True, "version": "test"}
        if path == "/project":
            return [{"id": "p1", "worktree": "/tmp/proj"}]
        if path.startswith("/session?directory="):
            return []
        if path.startswith("/session/") and path.endswith("/message"):
            session_id = path[len("/session/") : -len("/message")]
            message_api_calls.append(session_id)
            return session_messages[session_id]
        if path == "/session":
            return agent_sessions
        raise AssertionError(f"unexpected path {path}")

    def run_collect(db_path):
        message_api_calls.clear()
        original_fetch_json = exporter.fetch_json
        original_refresh_quotas = exporter.refresh_quotas
        exporter.fetch_json = fake_fetch_json
        exporter.refresh_quotas = lambda auth_path: None
        try:
            return exporter.collect("http://mock", "/dev/null", db_path).splitlines()
        finally:
            exporter.fetch_json = original_fetch_json
            exporter.refresh_quotas = original_refresh_quotas

    def check_agent_metrics(lines):
        check(
            "agent tokens zero-filled types",
            sum(1 for line in lines if line.startswith("opencode_agent_tokens_total{")),
            15,
        )
        check(
            "agent build input",
            'opencode_agent_tokens_total{agent="build",type="input",} 10' in lines,
            True,
        )
        check(
            "agent build output sums its messages",
            'opencode_agent_tokens_total{agent="build",type="output",} 27' in lines,
            True,
        )
        check(
            "agent build reasoning",
            'opencode_agent_tokens_total{agent="build",type="reasoning",} 1' in lines,
            True,
        )
        check(
            "agent build cache_read",
            'opencode_agent_tokens_total{agent="build",type="cache_read",} 2' in lines,
            True,
        )
        check(
            "agent build cache_write",
            'opencode_agent_tokens_total{agent="build",type="cache_write",} 3' in lines,
            True,
        )
        check(
            "agent plan input spans sessions",
            'opencode_agent_tokens_total{agent="plan",type="input",} 105' in lines,
            True,
        )
        check(
            "agent plan reasoning zero",
            'opencode_agent_tokens_total{agent="plan",type="reasoning",} 0' in lines,
            True,
        )
        check(
            "agent missing falls back to unknown",
            'opencode_agent_tokens_total{agent="unknown",type="input",} 1' in lines,
            True,
        )
        check(
            "agent unknown output from session fallback",
            'opencode_agent_tokens_total{agent="unknown",type="output",} 4' in lines,
            True,
        )
        check(
            "agent empty falls back to unknown",
            'opencode_agent_tokens_total{agent="unknown",type="cache_write",} 9'
            in lines,
            True,
        )
        check(
            "step-finish part tokens not counted",
            all(
                "999" not in line
                for line in lines
                if line.startswith("opencode_agent_")
            ),
            True,
        )
        check(
            "non-assistant messages not counted",
            'opencode_agent_tokens_total{agent="build",type="input",} 65'
            not in lines,
            True,
        )
        check(
            "agent cost build",
            'opencode_agent_cost_usd_total{agent="build",} 0.35' in lines,
            True,
        )
        check(
            "agent cost plan",
            'opencode_agent_cost_usd_total{agent="plan",} 0.4' in lines,
            True,
        )
        check(
            "agent cost unknown merges missing and empty",
            'opencode_agent_cost_usd_total{agent="unknown",} 0.25' in lines,
            True,
        )

    # Run 1: no database configured — every session uses the message API.
    collect_lines = run_collect(None)
    check(
        "api fallback calls every session without db",
        sorted(message_api_calls),
        ["s1", "s2", "s3", "s4"],
    )
    check(
        "agent tokens help",
        "# HELP opencode_agent_tokens_total Cumulative tokens per agent and token type, summed from assistant message info records."
        in collect_lines,
        True,
    )
    check(
        "agent tokens type counter",
        "# TYPE opencode_agent_tokens_total counter" in collect_lines,
        True,
    )
    check(
        "agent cost help",
        "# HELP opencode_agent_cost_usd_total Cumulative cost in USD per agent, summed from assistant message info records."
        in collect_lines,
        True,
    )
    check(
        "agent cost type counter",
        "# TYPE opencode_agent_cost_usd_total counter" in collect_lines,
        True,
    )
    check_agent_metrics(collect_lines)
    check(
        "session token totals unchanged",
        'opencode_session_tokens_total{type="input",} 16' in collect_lines,
        True,
    )
    check(
        "session cache totals unchanged",
        'opencode_session_tokens_total{type="cache_write",} 20' in collect_lines,
        True,
    )
    check(
        "session cost total unchanged",
        "opencode_session_cost_usd_total 1.25" in collect_lines,
        True,
    )
    check(
        "model provider normalization unchanged",
        'opencode_model_tokens_total{provider="zai",model="glm",type="input",} 5'
        in collect_lines,
        True,
    )
    check(
        "up still reported",
        "opencode_up 1" in collect_lines,
        True,
    )

    # Database-first aggregation: a temporary SQLite database shaped like
    # OpenCode's opencode-stable.db — message(session_id, data) holding the
    # message info JSON, session table marking known sessions. The DB
    # session.agent column is deliberately "stale-build" to prove the
    # fallback uses the session agent from the API session summaries.
    temp_dir = tempfile.TemporaryDirectory()
    db_path = os.path.join(temp_dir.name, "opencode-stable.db")
    connection = sqlite3.connect(db_path)
    connection.execute("CREATE TABLE session (id TEXT PRIMARY KEY, agent TEXT)")
    connection.execute(
        "CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, data TEXT)"
    )
    connection.executemany(
        "INSERT INTO session (id, agent) VALUES (?, ?)",
        [
            ("s1", "stale-build"),
            ("s2", "plan"),
            ("s0", "unused-agent"),
            ("s9", "session-agent"),
        ],
    )
    db_rows = []
    for db_session_id, envelopes in (
        ("s1", session_messages["s1"]),
        ("s2", session_messages["s2"]),
        (
            "s9",
            [
                {
                    "info": {
                        "role": "assistant",
                        "agent": "",
                        "cost": 0.1,
                        "tokens": {"input": 7},
                    }
                },
                {"info": {"role": "assistant", "cost": 0.0, "tokens": {"output": 3}}},
            ],
        ),
    ):
        for index, envelope in enumerate(envelopes):
            db_rows.append(
                (f"{db_session_id}-m{index}", db_session_id, json.dumps(envelope["info"]))
            )
    connection.executemany(
        "INSERT INTO message (id, session_id, data) VALUES (?, ?, ?)", db_rows
    )
    connection.commit()
    connection.close()

    db_agent_tokens, db_agent_cost, db_covered = exporter.agent_usage_from_db(
        db_path,
        {
            "s1": "build",
            "s2": "plan",
            "s0": "unused-agent",
            "s9": "session-agent",
            "s99": "ghost",
        },
    )
    check(
        "db covered sessions",
        db_covered,
        {"s1", "s2", "s0", "s9"},
    )
    check(
        "db message-free session mints no agent series",
        "unused-agent" in db_agent_tokens,
        False,
    )
    check(
        "db build tokens",
        db_agent_tokens["build"],
        {
            "input": 10,
            "output": 27,
            "reasoning": 1,
            "cache_read": 2,
            "cache_write": 3,
        },
    )
    check(
        "db plan tokens span sessions and empty agent",
        db_agent_tokens["plan"],
        {
            "input": 105,
            "output": 6,
            "reasoning": 0,
            "cache_read": 7,
            "cache_write": 8,
        },
    )
    check(
        "db empty-string agent falls back to session agent",
        db_agent_tokens["session-agent"],
        {
            "input": 7,
            "output": 3,
            "reasoning": 0,
            "cache_read": 0,
            "cache_write": 0,
        },
    )
    check("db build cost", db_agent_cost["build"], 0.35)
    check("db plan cost", db_agent_cost["plan"], 0.4)
    check("db session-agent cost", db_agent_cost["session-agent"], 0.1)

    try:
        exporter.agent_usage_from_db(
            os.path.join(temp_dir.name, "missing.db"), {"s1": "build"}
        )
        failures.append("agent usage from missing db: did not raise sqlite3.Error")
    except sqlite3.Error:
        pass
    except Exception as error:
        failures.append(
            f"agent usage from missing db: raised {type(error).__name__} "
            "instead of sqlite3.Error"
        )

    # Run 2: database covers s1/s2 only — they skip the message API while
    # s3/s4 still fall back to it, and the aggregate metrics are identical
    # to the API-only run.
    collect_lines = run_collect(db_path)
    check(
        "db-covered sessions skip the message api",
        sorted(message_api_calls),
        ["s3", "s4"],
    )
    check_agent_metrics(collect_lines)

    # Run 3: database covers every session — zero message API calls, and
    # sessions without messages mint no agent series. Session-level metrics
    # stay untouched.
    full_db_path = os.path.join(temp_dir.name, "full.db")
    connection = sqlite3.connect(full_db_path)
    connection.execute("CREATE TABLE session (id TEXT PRIMARY KEY, agent TEXT)")
    connection.execute(
        "CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, data TEXT)"
    )
    connection.executemany(
        "INSERT INTO session (id, agent) VALUES (?, ?)",
        [("s1", "build"), ("s2", "plan"), ("s3", ""), ("s4", "")],
    )
    connection.executemany(
        "INSERT INTO message (id, session_id, data) VALUES (?, ?, ?)", db_rows[0:5]
    )
    connection.commit()
    connection.close()
    collect_lines = run_collect(full_db_path)
    check("full db coverage makes no message api calls", message_api_calls, [])
    check(
        "full db coverage drops message-less agents",
        'opencode_agent_tokens_total{agent="unknown",type="input",} 1'
        in collect_lines,
        False,
    )
    check(
        "full db coverage keeps db agent metrics",
        'opencode_agent_tokens_total{agent="build",type="input",} 10'
        in collect_lines,
        True,
    )
    check(
        "full db coverage keeps session metrics",
        "opencode_session_cost_usd_total 1.25" in collect_lines,
        True,
    )

    # Run 4: unavailable database — the scrape still succeeds via the
    # message API for every session.
    collect_lines = run_collect(os.path.join(temp_dir.name, "missing.db"))
    check(
        "unavailable db falls back to the message api",
        sorted(message_api_calls),
        ["s1", "s2", "s3", "s4"],
    )
    check_agent_metrics(collect_lines)

    temp_dir.cleanup()

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        sys.exit(1)
    print("opencode-exporter tests passed")
    PYEOF

    touch "$out"
  ''
