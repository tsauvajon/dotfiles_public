# Integration tests for the OpenCode ops helper scripts.
{ pkgs, lib }:

let
  statusHelper = ./opencode-server-status.sh;
  reapHelper = ./opencode-reap.sh;
  procLib = ./lib/opencode-procs.sh;
in
pkgs.runCommand "opencode-ops-test"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.gnused
    ];
    inherit statusHelper reapHelper procLib;
  }
  ''
        set -eu

        fail() { echo "FAIL: $*" >&2; exit 1; }

        script_dir="$TMPDIR/scripts"
        mkdir -p "$script_dir/lib"
        install -m 0755 "$statusHelper" "$script_dir/opencode-server-status.sh"
        install -m 0755 "$reapHelper" "$script_dir/opencode-reap.sh"
        install -m 0644 "$procLib" "$script_dir/lib/opencode-procs.sh"
        statusHelper="$script_dir/opencode-server-status.sh"
        reapHelper="$script_dir/opencode-reap.sh"

        ps_fixture="$TMPDIR/processes.txt"
        cat > "$ps_fixture" <<'EOF'
    thomas 100 1 ?? 2-00:00:00 12345 /nix/store/example-opencode/bin/opencode attach http://127.0.0.1:4096 --dir /tmp/project
    thomas 101 42 ttys001 00:05:00 234 opencode attach http://127.0.0.1:4096 --dir /tmp/project
    thomas 102 1 ?? 3-00:00:00 345 opencode run --attach http://127.0.0.1:4096 prompt
    thomas 104 1 ?? 1-00:00:00 567 opencode attach http://127.0.0.1:4096 --dir /tmp/boundary
    thomas 105 1 ?? 08-00:00:01 678 opencode attach http://127.0.0.1:4096 --dir /tmp/leading-zero-day
    thomas 106 1 ?? 3-00:00:00 789 opencode attach http://localhost:4096 --dir /tmp/other-url
    thomas 200 1 ?? 1-01:00:00 456 opencode serve --hostname 127.0.0.1 --port 4096
    thomas 300 1 ?? 00:30:00 789 bare opencode
    thomas 777 1 ?? 00:10:00 987 opencode serve --hostname 127.0.0.1 --port 4096
    other 103 1 ?? 4-00:00:00 456 opencode attach http://127.0.0.1:4096 --dir /tmp/project
    EOF

        stdout_log="$TMPDIR/shared-server.log"
        stderr_log="$TMPDIR/shared-server-error.log"
        pending_file="$TMPDIR/pending-restart"
        systemd_show="$TMPDIR/systemd-show"
        launchctl_print="$TMPDIR/launchctl-print"
        printf 'normal line\nlistener warning: port was busy before restart\n' > "$stderr_log"
        printf 'hello\n' > "$stdout_log"
        printf 'reason=setup is running under an OpenCode agent with a healthy server\ncreated_at=2026-06-04T12:00:00Z\n' > "$pending_file"
        printf 'ActiveState=active\nSubState=running\nMainPID=200\n' > "$systemd_show"
        printf 'state = running\npid = 777\nactive count = 1\n' > "$launchctl_print"

        set +e
        output=$(OPENCODE_STATUS_UNAME=Linux \
          OPENCODE_STATUS_HEALTH=ok \
          OPENCODE_STATUS_USER=thomas \
          OPENCODE_STATUS_SYSTEMD_SHOW="$(cat "$systemd_show")" \
          OPENCODE_STATUS_PROCESS_FILE="$ps_fixture" \
          OPENCODE_SHARED_LOG_FILE="$stdout_log" \
          OPENCODE_SHARED_ERROR_LOG_FILE="$stderr_log" \
          OPENCODE_SHARED_PENDING_RESTART_FILE="$pending_file" \
          bash "$statusHelper" 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 0 ] || fail "status should exit 0, got $rc: $output"
        echo "$output" | grep -q '^  health: healthy$' || fail "status health missing: $output"
        echo "$output" | grep -q '^  service: active/running (service=opencode-server.service)$' || fail "systemd state missing: $output"
        echo "$output" | grep -q '^  pid: 200$' || fail "pid missing: $output"
        echo "$output" | grep -q '^  process: RSS 456 KiB, elapsed 1-01:00:00$' || fail "process stats missing: $output"
        echo "$output" | grep -q '^  attached TUI clients: 4$' || fail "attached count should ignore run --attach, other URLs, and other users: $output"
        echo "$output" | grep -q 'latest listener warning: listener warning: port was busy before restart' || fail "listener warning missing: $output"
        echo "$output" | grep -q 'pending restart file: .* (present (.*reason: setup is running under an OpenCode agent with a healthy server, created_at: 2026-06-04T12:00:00Z)' || fail "pending restart state missing: $output"

        set +e
        output=$(OPENCODE_STATUS_UNAME=Darwin \
          OPENCODE_STATUS_HEALTH=ok \
          OPENCODE_STATUS_USER=thomas \
          OPENCODE_STATUS_LAUNCHCTL_PRINT="$(cat "$launchctl_print")" \
          OPENCODE_STATUS_PROCESS_FILE="$ps_fixture" \
          OPENCODE_SHARED_LOG_FILE="$stdout_log" \
          OPENCODE_SHARED_ERROR_LOG_FILE="$stderr_log" \
          OPENCODE_SHARED_PENDING_RESTART_FILE="$pending_file" \
          bash "$statusHelper" 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 0 ] || fail "Darwin status should exit 0, got $rc: $output"
        echo "$output" | grep -q '^  service: running (active-count=1)$' || fail "launchctl state missing: $output"
        echo "$output" | grep -q '^  pid: 777$' || fail "launchctl pid missing: $output"

        kill_log="$TMPDIR/kill.log"
        set +e
        output=$(OPENCODE_REAP_USER=thomas \
          OPENCODE_REAP_PROCESS_FILE="$ps_fixture" \
          OPENCODE_REAP_KILL_LOG="$kill_log" \
          bash "$reapHelper" 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 0 ] || fail "dry-run reap should exit 0, got $rc: $output"
        echo "$output" | grep -q 'dry-run mode' || fail "dry-run mode missing: $output"
        echo "$output" | grep -q 'would signal pid 100' || fail "dry-run should include stale orphan attach client: $output"
        echo "$output" | grep -q 'would signal pid 105' || fail "dry-run should parse leading-zero days as decimal: $output"
        ! echo "$output" | grep -q 'pid 101' || fail "reap should ignore non-orphan tty client: $output"
        ! echo "$output" | grep -q 'pid 102' || fail "reap should ignore run --attach: $output"
        ! echo "$output" | grep -q 'pid 104' || fail "reap should ignore clients exactly at age threshold: $output"
        ! echo "$output" | grep -q 'pid 106' || fail "reap should ignore attach clients for other URLs: $output"
        ! echo "$output" | grep -q 'pid 200' || fail "reap should ignore serve: $output"
        [ ! -e "$kill_log" ] || fail "dry-run must not signal processes"

        set +e
        output=$(OPENCODE_REAP_USER=thomas \
          OPENCODE_REAP_PROCESS_FILE="$ps_fixture" \
          OPENCODE_REAP_KILL_LOG="$kill_log" \
          bash "$reapHelper" --apply --signal=TERM 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 0 ] || fail "apply reap should exit 0, got $rc: $output"
        echo "$output" | grep -q 'signaling pid 100' || fail "apply should signal stale orphan attach client: $output"
        grep -qx 'TERM 100' "$kill_log" || fail "TERM signal for pid 100 missing: $(cat "$kill_log")"
        grep -qx 'TERM 105' "$kill_log" || fail "TERM signal for pid 105 missing: $(cat "$kill_log")"
        [ "$(wc -l < "$kill_log" | tr -d '[:space:]')" = 2 ] || fail "apply should signal only stale matching-url clients with TERM: $(cat "$kill_log")"

        : > "$kill_log"
        set +e
        output=$(OPENCODE_REAP_USER=thomas \
          OPENCODE_REAP_PROCESS_FILE="$ps_fixture" \
          OPENCODE_REAP_KILL_LOG="$kill_log" \
          bash "$reapHelper" --apply --force --older-than=7d 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 0 ] || fail "force reap should exit 0, got $rc: $output"
        [ "$(cat "$kill_log")" = 'KILL 105' ] || fail "--force should signal only pid 105 with KILL: $(cat "$kill_log")"

        set +e
        output=$(OPENCODE_REAP_USER=thomas \
          OPENCODE_REAP_PROCESS_FILE="$ps_fixture" \
          bash "$reapHelper" --older-than 1w 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 64 ] || fail "invalid duration should exit 64, got $rc: $output"

        set +e
        output=$(OPENCODE_REAP_USER=thomas \
          OPENCODE_REAP_PROCESS_FILE="$ps_fixture" \
          bash "$reapHelper" --signal BANANA 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 64 ] || fail "invalid signal should exit 64, got $rc: $output"

        set +e
        output=$(OPENCODE_REAP_USER=thomas \
          OPENCODE_REAP_PROCESS_FILE="$ps_fixture" \
          bash "$reapHelper" --older-than 9d 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 0 ] || fail "empty reap should exit 0, got $rc: $output"
        echo "$output" | grep -q 'no stale orphaned attach clients found' || fail "empty result message missing: $output"

        echo "all opencode ops assertions passed"
        touch "$out"
  ''
