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
    import subprocess
    import sys
    import tempfile
    import threading
    import urllib.error
    import urllib.request

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

    def check_pricing_raises(name, func):
        try:
            func()
        except exporter.PricingError:
            return
        except Exception as error:
            failures.append(f"{name}: raised {type(error).__name__} instead of PricingError")
            return
        failures.append(f"{name}: did not raise PricingError")

    collect_calls = []
    original_collect = exporter.collect

    def fail_collect(*args, **kwargs):
        collect_calls.append((args, kwargs))
        raise AssertionError("health endpoint invoked collection")

    exporter.collect = fail_collect
    http_server = exporter.ThreadingHTTPServer(
        ("127.0.0.1", 0), exporter.MetricsHandler
    )
    http_thread = threading.Thread(target=http_server.serve_forever)
    http_thread.start()
    try:
        base_url = f"http://127.0.0.1:{http_server.server_address[1]}"
        with urllib.request.urlopen(f"{base_url}/health", timeout=2) as response:
            check("health status", response.status, 200)
            check("health content type", response.headers.get_content_type(), "text/plain")
            check("health body", response.read(), b"OK\n")
        check("health skips collection", collect_calls, [])
        try:
            urllib.request.urlopen(f"{base_url}/unknown", timeout=2)
        except urllib.error.HTTPError as error:
            check("unknown path status", error.code, 404)
        else:
            failures.append("unknown path status: expected HTTP 404")
    finally:
        http_server.shutdown()
        http_server.server_close()
        http_thread.join(timeout=2)
        exporter.collect = original_collect

    check("health server stopped", http_thread.is_alive(), False)

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

    pricing_document = {
        "provider": {
            "test": {
                "models": {
                    "priced": {
                        "cost": {
                            "input": 2,
                            "output": 10,
                            "cache_read": 0.2,
                            "cache_write": 2.5,
                            "context_over_200k": {
                                "input": 4,
                                "output": 15,
                                "cache_read": 0.4,
                                "cache_write": 5,
                            },
                        }
                    }
                }
            }
        }
    }
    with tempfile.TemporaryDirectory() as pricing_dir:
        pricing_path = os.path.join(pricing_dir, "pricing.json")
        with open(pricing_path, "w", encoding="utf-8") as handle:
            json.dump(pricing_document, handle)
        pricing = exporter.load_pricing_file(pricing_path)
        check("pricing provider/model loaded", sorted(pricing), [("test", "priced")])
        tokens = {
            "input": 1000,
            "output": 200,
            "reasoning": 50,
            "cache_read": 500,
            "cache_write": 100,
        }
        cost, estimated, missing = exporter.priced_usage(
            "test", "priced", tokens, 0, pricing
        )
        check_close("pricing formula includes reasoning and cache", cost, 0.00485)
        check_close("pricing estimate subtotal", estimated, cost)
        check("known pricing is not missing", missing, False)
        for invalid_cost in (-1, float("nan"), float("inf"), "invalid", "1.25", True):
            cost, estimated, missing = exporter.priced_usage(
                "test", "priced", tokens, invalid_cost, pricing
            )
            check_close(f"invalid reported cost falls back: {invalid_cost!r}", cost, 0.00485)
        partial_cost, partial_estimated, partial_missing = exporter.priced_usage(
            "test", "priced", {"output": 100}, 0, pricing
        )
        check_close("partial token mapping cost", partial_cost, 0.001)
        check_close("partial token mapping estimate", partial_estimated, 0.001)
        check("partial token mapping pricing known", partial_missing, False)
        long_tokens = dict(tokens, input=200001)
        cost, estimated, missing = exporter.priced_usage(
            "test", "priced", long_tokens, None, pricing
        )
        check_close("over 200k pricing tier", cost, 0.804454)
        cost, estimated, missing = exporter.priced_usage(
            "test", "priced", long_tokens, 1.25, pricing
        )
        check("positive reported cost wins", cost, 1.25)
        check("reported cost has no estimate", estimated, 0.0)
        zero_tokens = {token_type: 0 for token_type in exporter.TOKEN_TYPES}
        check(
            "zero usage estimates zero",
            exporter.priced_usage("test", "priced", zero_tokens, 0, pricing),
            (0.0, 0.0, False),
        )
        check(
            "unknown usage stays zero and is missing",
            exporter.priced_usage("local", "free", tokens, 0, pricing),
            (0.0, 0.0, True),
        )

        malformed_path = os.path.join(pricing_dir, "malformed.json")
        with open(malformed_path, "w", encoding="utf-8") as handle:
            json.dump(
                {
                    "provider": {
                        "test": {
                            "models": {
                                "bad": {
                                    "cost": {
                                        "input": -1,
                                        "output": 1,
                                        "cache_read": 0,
                                        "cache_write": 0,
                                    }
                                }
                            }
                        }
                    }
                },
                handle,
            )
        check_pricing_raises(
            "malformed pricing validation",
            lambda: exporter.load_pricing_file(malformed_path),
        )
        result = subprocess.run(
            [sys.executable, module_path, "--pricing-file", malformed_path],
            text=True,
            capture_output=True,
            check=False,
        )
        check("malformed pricing CLI exit", result.returncode, 2)
        check(
            "malformed pricing CLI error",
            "invalid pricing file" in result.stderr,
            True,
        )
        for name, invalid_value in (("nonnumeric", "free"), ("nonfinite", float("nan"))):
            invalid_document = json.loads(json.dumps(pricing_document))
            invalid_document["provider"]["test"]["models"]["priced"]["cost"]["input"] = invalid_value
            invalid_path = os.path.join(pricing_dir, f"{name}.json")
            with open(invalid_path, "w", encoding="utf-8") as handle:
                json.dump(invalid_document, handle)
            check_pricing_raises(
                f"{name} pricing validation",
                lambda path=invalid_path: exporter.load_pricing_file(path),
            )

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

    # Expected attribution from these envelopes (provider/model fall back to
    # "unknown" when the message info carries none):
    #   build@zai/glm:        input 10, output 20, reasoning 1,
    #                         cache_read 2, cache_write 3
    #                         (m1; m3's cost lands on the build agent too
    #                         because a missing message agent falls back to
    #                         the session agent, and m5 costs nothing)
    #   build@unknown:        output 7, cost 0.05  (m3 carries no model
    #                         info)
    #   build@openai/gpt:     input 5, cost 0  (m5: same agent on a second
    #                         model stays a separate bucket)
    #   plan@openai/gpt:      input 105, output 6, reasoning 0,
    #                         cache_read 7, cache_write 8, cost 0.40
    #                         (s1 m2 + s2 m1: one session can feed several
    #                         agents, one agent/model can span sessions)
    #   unknown@unknown:      input 1, output 4, cache_write 9, cost 0.50
    #                         (s3: no message agent/model and no session
    #                         agent; s4 has no messages, so its summary cost
    #                         is retained without minting token/stat series)
    session_messages = {
        "s1": [
            {
                "info": {
                    "role": "assistant",
                    "agent": "build",
                    "providerID": "zai-coding-plan",
                    "modelID": "glm",
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
                    "providerID": "openai",
                    "modelID": "gpt",
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
            {
                "info": {
                    "role": "assistant",
                    "agent": "build",
                    "providerID": "openai",
                    "modelID": "gpt",
                    "cost": 0,
                    "tokens": {"input": 5},
                },
                "parts": [],
            },
        ],
        "s2": [
            {
                "info": {
                    "role": "assistant",
                    "providerID": "openai",
                    "modelID": "gpt",
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
            25,
        )
        check(
            "agent build glm input",
            'opencode_agent_tokens_total{agent="build",model="glm",provider="zai",type="input",} 10'
            in lines,
            True,
        )
        check(
            "agent build glm output",
            'opencode_agent_tokens_total{agent="build",model="glm",provider="zai",type="output",} 20'
            in lines,
            True,
        )
        check(
            "agent build glm reasoning",
            'opencode_agent_tokens_total{agent="build",model="glm",provider="zai",type="reasoning",} 1'
            in lines,
            True,
        )
        check(
            "agent build glm cache_read",
            'opencode_agent_tokens_total{agent="build",model="glm",provider="zai",type="cache_read",} 2'
            in lines,
            True,
        )
        check(
            "agent build glm cache_write",
            'opencode_agent_tokens_total{agent="build",model="glm",provider="zai",type="cache_write",} 3'
            in lines,
            True,
        )
        check(
            "agent build gpt is a separate model bucket",
            'opencode_agent_tokens_total{agent="build",model="gpt",provider="openai",type="input",} 5'
            in lines,
            True,
        )
        check(
            "agent build gpt zero-fills missing types",
            'opencode_agent_tokens_total{agent="build",model="gpt",provider="openai",type="output",} 0'
            in lines,
            True,
        )
        check(
            "agent session-fallback tokens without model info stay separate",
            'opencode_agent_tokens_total{agent="build",model="unknown",provider="unknown",type="output",} 7'
            in lines,
            True,
        )
        check(
            "agent plan input spans sessions",
            'opencode_agent_tokens_total{agent="plan",model="gpt",provider="openai",type="input",} 105'
            in lines,
            True,
        )
        check(
            "agent plan reasoning zero",
            'opencode_agent_tokens_total{agent="plan",model="gpt",provider="openai",type="reasoning",} 0'
            in lines,
            True,
        )
        check(
            "agent missing falls back to unknown",
            'opencode_agent_tokens_total{agent="unknown",model="unknown",provider="unknown",type="input",} 1'
            in lines,
            True,
        )
        check(
            "agent unknown output from session fallback",
            'opencode_agent_tokens_total{agent="unknown",model="unknown",provider="unknown",type="output",} 4'
            in lines,
            True,
        )
        check(
            "agent empty falls back to unknown",
            'opencode_agent_tokens_total{agent="unknown",model="unknown",provider="unknown",type="cache_write",} 9'
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
            'opencode_agent_tokens_total{agent="build",model="glm",provider="zai",type="input",} 65'
            not in lines,
            True,
        )
        check(
            "zai coding plan provider normalized",
            all('provider="zai-coding-plan"' not in line for line in lines),
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
            'opencode_agent_cost_usd_total{agent="unknown",} 0.5' in lines,
            True,
        )
        check(
            "agent session stats zero-filled",
            sum(
                1
                for line in lines
                if line.startswith("opencode_agent_session_tokens{")
            ),
            100,
        )
        check(
            "agent session stats help",
            "# HELP opencode_agent_session_tokens Token distribution per agent, provider/model and token type over per-session totals (stat label: p10, p50, p90, mean); gauge, not a counter."
            in lines,
            True,
        )
        check(
            "agent session stats type gauge",
            "# TYPE opencode_agent_session_tokens gauge" in lines,
            True,
        )
        check(
            "single-session quantiles collapse to the value",
            'opencode_agent_session_tokens{agent="build",model="glm",provider="zai",type="input",stat="p10",} 10.0'
            in lines,
            True,
        )
        check(
            "multi-session p10 interpolates",
            'opencode_agent_session_tokens{agent="plan",model="gpt",provider="openai",type="input",stat="p10",} 14.5'
            in lines,
            True,
        )
        check(
            "multi-session p50 interpolates",
            'opencode_agent_session_tokens{agent="plan",model="gpt",provider="openai",type="input",stat="p50",} 52.5'
            in lines,
            True,
        )
        check(
            "multi-session p90 interpolates",
            'opencode_agent_session_tokens{agent="plan",model="gpt",provider="openai",type="input",stat="p90",} 90.5'
            in lines,
            True,
        )
        check(
            "multi-session mean averages",
            'opencode_agent_session_tokens{agent="plan",model="gpt",provider="openai",type="input",stat="mean",} 52.5'
            in lines,
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
        "# HELP opencode_agent_tokens_total Cumulative tokens per agent, provider/model and token type, summed from assistant message info records."
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
        "# HELP opencode_agent_cost_usd_total Cumulative cost in USD per agent from reported costs plus pricing fallback estimates."
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
        "default pricing preserves session summary cost total",
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

    db_groups, db_covered = exporter.message_usage_from_db(
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
    check("quantile of empty list", exporter.quantile([], 0.5), 0.0)
    check("quantile of single value", exporter.quantile([7], 0.9), 7.0)
    check("quantile interpolates at the ends", exporter.quantile([5, 100], 0.1), 14.5)
    check(
        "quantile interpolates in the middle",
        exporter.quantile([1, 2, 3, 4], 0.5),
        2.5,
    )

    def session_sample_value(token_type, stat):
        for labels, value in session_samples:
            if labels[3][1] == token_type and labels[4][1] == stat:
                return value
        return None

    session_samples = exporter.agent_session_token_samples(
        {
            ("plan", "openai", "gpt"): {
                "input": [100, 5],
                "output": [6],
                "reasoning": [],
                "cache_read": [],
                "cache_write": [],
            }
        }
    )
    check(
        "session samples emit p10 p50 p90 mean per type",
        [
            labels[4][1]
            for labels, _ in session_samples
            if labels[3][1] == "input"
        ],
        ["p10", "p50", "p90", "mean"],
    )
    check("session samples input p10", session_sample_value("input", "p10"), 14.5)
    check("session samples input p50", session_sample_value("input", "p50"), 52.5)
    check("session samples input p90", session_sample_value("input", "p90"), 90.5)
    check("session samples input mean", session_sample_value("input", "mean"), 52.5)
    check(
        "session samples single-session mean",
        session_sample_value("output", "mean"),
        6.0,
    )
    check(
        "session samples empty type falls back to zero",
        session_sample_value("reasoning", "p50"),
        0.0,
    )
    grouped_agents = {}
    grouped_cost = {}
    grouped_sessions = {}
    for group in db_groups:
        key = (group["agent"], group["provider"], group["model"])
        bucket = grouped_agents.setdefault(
            key, {token_type: 0 for token_type in exporter.TOKEN_TYPES}
        )
        session_bucket = grouped_sessions.setdefault(group["session_id"], {})
        per_session = session_bucket.setdefault(
            key, {token_type: 0 for token_type in exporter.TOKEN_TYPES}
        )
        for token_type, value in group["tokens"].items():
            bucket[token_type] += value
            per_session[token_type] += value
        grouped_cost[group["agent"]] = grouped_cost.get(group["agent"], 0) + group["reported_cost"]
    check("db message-free session mints no agent series", any(key[0] == "unused-agent" for key in grouped_agents), False)
    check("db raw provider retained", grouped_agents[("build", "zai-coding-plan", "glm")]["input"], 10)
    check("db build second model retained", grouped_agents[("build", "openai", "gpt")]["input"], 5)
    check("db model-less usage retained separately", grouped_agents[("build", "unknown", "unknown")]["output"], 7)
    check("db plan spans sessions", grouped_agents[("plan", "openai", "gpt")]["input"], 105)
    check("db empty agent session fallback", grouped_agents[("session-agent", "unknown", "unknown")]["input"], 7)
    check("db build reported cost", grouped_cost["build"], 0.35)
    check("db plan reported cost", grouped_cost["plan"], 0.4)
    check("db session-agent reported cost", grouped_cost["session-agent"], 0.1)
    check("db per-session group keeps session id", grouped_sessions["s1"][("plan", "openai", "gpt")]["input"], 100)
    check(
        "db per-session keeps every provider/model tuple",
        sorted(grouped_sessions["s1"]),
        [
            ("build", "openai", "gpt"),
            ("build", "unknown", "unknown"),
            ("build", "zai-coding-plan", "glm"),
            ("plan", "openai", "gpt"),
        ],
    )

    try:
        exporter.message_usage_from_db(
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
        "INSERT INTO message (id, session_id, data) VALUES (?, ?, ?)", db_rows[0:6]
    )
    connection.commit()
    connection.close()
    collect_lines = run_collect(full_db_path)
    check("full db coverage makes no message api calls", message_api_calls, [])
    check(
        "full db coverage drops message-less agents",
        'opencode_agent_tokens_total{agent="unknown",model="unknown",provider="unknown",type="input",} 1'
        in collect_lines,
        False,
    )
    check(
        "full db coverage drops message-less session stats",
        'opencode_agent_session_tokens{agent="unknown",model="unknown",provider="unknown",type="input",stat="p50",}'
        in collect_lines,
        False,
    )
    check(
        "full db coverage keeps db agent metrics",
        'opencode_agent_tokens_total{agent="build",model="glm",provider="zai",type="input",} 10'
        in collect_lines,
        True,
    )
    check(
        "full db coverage preserves summaries for message-free sessions",
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

    # Mixed DB groups preserve per-request reported-vs-estimated and context
    # tier decisions while still using one grouped query.
    mixed_db_path = os.path.join(temp_dir.name, "mixed.db")
    connection = sqlite3.connect(mixed_db_path)
    connection.execute("CREATE TABLE session (id TEXT PRIMARY KEY, agent TEXT)")
    connection.execute("CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, data TEXT)")
    connection.execute("INSERT INTO session (id, agent) VALUES ('d1', 'build')")
    connection.executemany(
        "INSERT INTO message (id, session_id, data) VALUES (?, 'd1', ?)",
        [
            ("reported", json.dumps({"role": "assistant", "agent": "build", "providerID": "test", "modelID": "priced", "cost": 0.5, "tokens": {"input": 10}})),
            ("short", json.dumps({"role": "assistant", "agent": "build", "providerID": "test", "modelID": "priced", "cost": 0, "tokens": {"input": 100}})),
            ("long", json.dumps({"role": "assistant", "agent": "build", "providerID": "test", "modelID": "priced", "tokens": {"input": 200001}})),
        ],
    )
    connection.commit()
    connection.close()
    mixed_groups, mixed_covered = exporter.message_usage_from_db(
        mixed_db_path, {"d1": "build"}
    )
    check("mixed DB coverage", mixed_covered, {"d1"})
    check("mixed DB group count", len(mixed_groups), 3)
    mixed_cost = 0
    mixed_estimated = 0
    for group in mixed_groups:
        cost, estimated, missing = exporter.priced_usage(
            group["provider"],
            group["model"],
            group["tokens"],
            group["reported_cost"],
            pricing,
            group["context_over_200k"],
        )
        mixed_cost += cost
        mixed_estimated += estimated
    check_close("mixed DB reported plus fallback", mixed_cost, 1.300204)
    check_close("mixed DB estimated subtotal", mixed_estimated, 0.800204)

    # API message info drives all cost dimensions. The first session's large
    # summary cost must not be added; the second session uses its summary only
    # because its message endpoint is unavailable.
    pricing_sessions = [
        {
            "id": "p1",
            "agent": "build",
            "cost": 99,
            "tokens": {"input": 1},
            "model": {"providerID": "test", "id": "priced"},
        },
        {
            "id": "p2",
            "agent": "plan",
            "cost": 0.4,
            "tokens": {},
            "model": {"providerID": "test", "id": "priced"},
        },
        {
            "id": "p3",
            "agent": "summary",
            "cost": 0,
            "tokens": {"input": 300000},
            "model": {"providerID": "test", "id": "priced"},
        },
    ]
    pricing_messages = [
        {"info": {"role": "assistant", "agent": "build", "providerID": "test", "modelID": "priced", "cost": 0.7, "tokens": {"input": 999999}}},
        {"info": {"role": "assistant", "agent": "build", "providerID": "test", "modelID": "priced", "cost": 0, "tokens": {"input": 1000000, "output": 100000, "reasoning": 100000, "cache": {"read": 500000, "write": 100000}}}},
        {"info": {"role": "assistant", "agent": "scout", "providerID": "local", "modelID": "free", "cost": None, "tokens": {"input": 10}}},
        {"info": {"role": "assistant", "agent": "reporter", "providerID": "reported-only", "modelID": "persisted", "cost": 0.2, "tokens": {"input": 10}}},
    ]

    def pricing_fetch_json(server_url, path):
        if path == "/global/health":
            return {"healthy": True, "version": "test"}
        if path == "/project":
            return []
        if path == "/session":
            return pricing_sessions
        if path == "/session/p1/message":
            return pricing_messages
        if path == "/session/p2/message":
            raise exporter.ServerError("unavailable")
        if path == "/session/p3/message":
            raise exporter.ServerError("unavailable")
        raise AssertionError(f"unexpected pricing path {path}")

    original_fetch_json = exporter.fetch_json
    original_refresh_quotas = exporter.refresh_quotas
    exporter.fetch_json = pricing_fetch_json
    exporter.refresh_quotas = lambda auth_path: None
    try:
        pricing_lines = exporter.collect(
            "http://mock", "/dev/null", None, pricing
        ).splitlines()
    finally:
        exporter.fetch_json = original_fetch_json
        exporter.refresh_quotas = original_refresh_quotas
    check("API reported plus estimate plus unavailable summaries", "opencode_session_cost_usd_total 9.6" in pricing_lines, True)
    check("API cost by model coherent", 'opencode_model_cost_usd_total{provider="test",model="priced",} 9.4' in pricing_lines, True)
    check("API cost by agent estimate", 'opencode_agent_cost_usd_total{agent="build",} 8.4' in pricing_lines, True)
    check("API unavailable summary by agent", 'opencode_agent_cost_usd_total{agent="plan",} 0.4' in pricing_lines, True)
    check("summary over 200k conservatively uses base tier", 'opencode_agent_cost_usd_total{agent="summary",} 0.6' in pricing_lines, True)
    check("estimated audit metric", 'opencode_model_estimated_cost_usd_total{provider="test",model="priced",} 8.3' in pricing_lines, True)
    check("unknown model missing pricing", 'opencode_pricing_missing{provider="local",model="free",} 1' in pricing_lines, True)
    check("priced model emits nonmissing zero", 'opencode_pricing_missing{provider="test",model="priced",} 0' in pricing_lines, True)
    check("reported-only model emits nonmissing zero", 'opencode_pricing_missing{provider="reported-only",model="persisted",} 0' in pricing_lines, True)
    check("positive reported not estimated twice", 'opencode_model_estimated_cost_usd_total{provider="test",model="priced",} 8.4' in pricing_lines, False)

    def metric_sum(lines, metric):
        return sum(
            float(line.rsplit(" ", 1)[1])
            for line in lines
            if line.startswith(f"{metric} ") or line.startswith(f"{metric}{{")
        )

    session_cost = metric_sum(pricing_lines, "opencode_session_cost_usd_total")
    model_cost = metric_sum(pricing_lines, "opencode_model_cost_usd_total")
    agent_cost = metric_sum(pricing_lines, "opencode_agent_cost_usd_total")
    check_close("session and model costs reconcile", session_cost, model_cost)
    check_close("session and agent costs reconcile", session_cost, agent_cost)

    # With the production default pricing={}, session summaries supply the
    # remainder after valid message costs. Empty/no-valid message lists fall
    # back completely, while malformed reported costs cannot become costs.
    fallback_sessions = [
        {"id": "f1", "agent": "summary", "cost": 1.0, "tokens": {}, "model": {"providerID": "test", "id": "priced"}},
        {"id": "f2", "agent": "empty", "cost": 0.5, "tokens": {}, "model": {"providerID": "local", "id": "free"}},
        {"id": "f3", "agent": "malformed", "cost": 0.25, "tokens": {}, "model": {"providerID": "test", "id": "priced"}},
        {"id": "f4", "agent": "invalid-list", "cost": 0.3, "tokens": {}, "model": {"providerID": "local", "id": "free"}},
    ]
    fallback_messages = {
        "f1": [
            {"info": {"role": "assistant", "agent": "build", "providerID": "test", "modelID": "priced", "cost": 0.4, "tokens": {"output": 1}}},
            {"info": {"role": "assistant", "agent": "plan", "providerID": "test", "modelID": "priced", "cost": 0, "tokens": {"cache": {"read": 1}}}},
        ],
        "f2": [],
        "f3": [
            {"info": {"role": "assistant", "agent": "malformed", "providerID": "test", "modelID": "priced", "cost": "0.9", "tokens": {"input": 1}}},
            {"info": {"role": "assistant", "agent": "malformed", "providerID": "test", "modelID": "priced", "cost": True, "tokens": {"output": 1}}},
        ],
        "f4": [{"info": {"role": "user", "cost": 100}}],
    }

    def fallback_fetch_json(server_url, path):
        if path == "/global/health":
            return {"healthy": True, "version": "test"}
        if path == "/project":
            return []
        if path == "/session":
            return fallback_sessions
        if path.startswith("/session/") and path.endswith("/message"):
            return fallback_messages[path[len("/session/") : -len("/message")]]
        raise AssertionError(f"unexpected fallback path {path}")

    exporter.fetch_json = fallback_fetch_json
    exporter.refresh_quotas = lambda auth_path: None
    try:
        fallback_lines = exporter.collect(
            "http://mock", "/dev/null", None, {}
        ).splitlines()
    finally:
        exporter.fetch_json = original_fetch_json
        exporter.refresh_quotas = original_refresh_quotas
    check("default pricing keeps summary total", "opencode_session_cost_usd_total 2.05" in fallback_lines, True)
    check("default pricing keeps valid message attribution", 'opencode_agent_cost_usd_total{agent="build",} 0.4' in fallback_lines, True)
    check("default pricing attributes zero-cost remainder", 'opencode_agent_cost_usd_total{agent="summary",} 0.6' in fallback_lines, True)
    check("empty message list uses summary", 'opencode_agent_cost_usd_total{agent="empty",} 0.5' in fallback_lines, True)
    check("malformed message costs use summary remainder", 'opencode_agent_cost_usd_total{agent="malformed",} 0.25' in fallback_lines, True)
    check("no valid assistant info uses summary", 'opencode_agent_cost_usd_total{agent="invalid-list",} 0.3' in fallback_lines, True)
    fallback_session_cost = metric_sum(fallback_lines, "opencode_session_cost_usd_total")
    check_close("default session and model costs reconcile", fallback_session_cost, metric_sum(fallback_lines, "opencode_model_cost_usd_total"))
    check_close("default session and agent costs reconcile", fallback_session_cost, metric_sum(fallback_lines, "opencode_agent_cost_usd_total"))

    temp_dir.cleanup()

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        sys.exit(1)
    print("opencode-exporter tests passed")
    PYEOF

    touch "$out"
  ''
