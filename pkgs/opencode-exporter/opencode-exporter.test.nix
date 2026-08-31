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
    import sys

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
    check("zai 1 month", exporter.zai_window_label({"unit": 6, "number": 1}), "1mo")
    check("zai 1 week", exporter.zai_window_label({"unit": 5, "number": 1}), "1w")
    check("zai tokens fallback", exporter.zai_window_label({"type": "TOKENS_LIMIT"}), "5h")
    check("zai time fallback", exporter.zai_window_label({"type": "TIME_LIMIT"}), "1mo")
    check("zai unknown", exporter.zai_window_label({}), "unknown")

    check("label seconds 5h", exporter.window_label_to_seconds("5h"), 18000)
    check("label seconds 1w", exporter.window_label_to_seconds("1w"), 604800)
    check("label seconds 1mo", exporter.window_label_to_seconds("1mo"), 2592000)
    check("label seconds unknown", exporter.window_label_to_seconds("unknown"), 0)

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
    check("openai 5h window seconds", five_hour["window_seconds"], 18000)
    check("openai 5h no credits", five_hour["limit_credits"], None)
    check("openai 1w label", weekly["window"], "1w")
    check("openai 1w window seconds", weekly["window_seconds"], 604800)
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
    monthly = by_window["1mo"]
    check_close("zai 5h used", five["used_ratio"], 522 / 2000)
    check_close("zai 5h remaining", five["remaining_ratio"], 1477 / 2000)
    check("zai 5h limit credits", five["limit_credits"], 2000.0)
    check("zai 5h used credits", five["used_credits"], 522.0)
    check("zai 5h reset", five["reset_seconds"], 1788186091.775)
    check("zai 5h window seconds", five["window_seconds"], 18000)
    check_close("zai 1mo used", monthly["used_ratio"], 522 / 10000)
    check_close("zai 1mo remaining", monthly["remaining_ratio"], 9477 / 10000)
    check("zai 1mo limit credits", monthly["limit_credits"], 10000.0)
    check("zai 1mo window seconds", monthly["window_seconds"], 2592000)

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

    if failures:
        for failure in failures:
            print(f"FAIL: {failure}", file=sys.stderr)
        sys.exit(1)
    print("opencode-exporter tests passed")
    PYEOF

    touch "$out"
  ''
