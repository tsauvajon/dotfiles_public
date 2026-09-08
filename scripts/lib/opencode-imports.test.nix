# Integration test for scripts/lib/opencode-imports.sh.
{ pkgs, lib }:

let
  helper = ./opencode-imports.sh;
in
pkgs.runCommand "opencode-imports-test"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
    ];
    inherit helper;
  }
  ''
    set -eu

    fail() { echo "FAIL: $*" >&2; exit 1; }

    home="$TMPDIR/home"
    mkdir -p "$home"

    run_sync() {
      local stage="$1"
      local manifest="$2"
      printf '%s' "$manifest" | HOME="$home" bash -c '. "$1"; opencode_imports_sync "$2"' _ "$helper" "$stage"
    }

    run_sync_faulted() {
      local stage="$1"
      local manifest="$2"
      printf '%s' "$manifest" | HOME="$home" \
        PATH="$fault_bin:$PATH" \
        REAL_MKTEMP="$real_mktemp" \
        REAL_MV="$real_mv" \
        FAULT_STATE="$fault_state" \
        FAULT_MKTEMP="''${fault_mktemp:-}" \
        FAULT_MV="''${fault_mv:-}" \
        bash -c '. "$1"; opencode_imports_sync "$2"' _ "$helper" "$stage"
    }

    assert_file() {
      [ -f "$1" ] || fail "expected file: $1"
    }

    assert_no_path() {
      [ ! -e "$1" ] || fail "unexpected path exists: $1"
    }

    make_source() {
      local src="$1"
      mkdir -p "$src/commands" "$src/skills/example-skill" "$src/agents" "$src/plugins" "$src/rules"
      printf 'command\n' > "$src/commands/hello.md"
      printf 'skill\n' > "$src/skills/example-skill/SKILL.md"
      printf 'agent\n' > "$src/agents/review.md"
      printf 'plugin\n' > "$src/plugins/example.ts"
      printf 'rule\n' > "$src/rules/10-rule.md"
      printf '{"fragment":true}\n' > "$src/opencode.fragment.json"
      printf '{"bare":true}\n' > "$src/opencode.json"
      printf '{"scripts":{}}\n' > "$src/package.json"
      printf '{"nonstandard":true}\n' > "$src/mcp.fragment.json"
      ln -s hello.md "$src/commands/linked.md"
      ln -s example-skill "$src/skills/linked-skill"
    }

    src="$TMPDIR/src"
    make_source "$src"

    # --- Test 1: auto-discovery stages standard trees and selected top-level files.
    stage1="$TMPDIR/stage1"
    manifest1=$(printf 'HEADER\tauto\t%s\tauto\nEND\tauto\n' "$src")
    run_sync "$stage1" "$manifest1" >/dev/null
    assert_file "$stage1/auto/commands/hello.md"
    assert_file "$stage1/auto/skills/example-skill/SKILL.md"
    assert_file "$stage1/auto/agents/review.md"
    assert_file "$stage1/auto/plugins/example.ts"
    assert_file "$stage1/auto/rules/10-rule.md"
    assert_file "$stage1/auto/opencode.fragment.json"
    assert_file "$stage1/auto/package.json"
    assert_no_path "$stage1/auto/opencode.json"
    [ ! -L "$stage1/auto/commands/linked.md" ] || fail "staged file symlink was not dereferenced"
    [ ! -L "$stage1/auto/skills/linked-skill" ] || fail "staged directory symlink was not dereferenced"
    assert_file "$stage1/auto/skills/linked-skill/SKILL.md"

    # --- Test 2: exclude filtering skips auto-discovered entries.
    stage2="$TMPDIR/stage2"
    manifest2=$(printf 'HEADER\texclude\t%s\tauto\nEXCLUDE\texclude\tcommands/hello.md\nEND\texclude\n' "$src")
    run_sync "$stage2" "$manifest2" >/dev/null
    assert_no_path "$stage2/exclude/commands/hello.md"
    assert_file "$stage2/exclude/package.json"

    # --- Test 3: rename rewrites auto-discovered destinations.
    stage3="$TMPDIR/stage3"
    manifest3=$(printf 'HEADER\trename-auto\t%s\tauto\nRENAME\trename-auto\tcommands/hello.md\tcommands/renamed.md\nEND\trename-auto\n' "$src")
    run_sync "$stage3" "$manifest3" >/dev/null
    assert_file "$stage3/rename-auto/commands/renamed.md"
    assert_no_path "$stage3/rename-auto/commands/hello.md"

    # --- Test 4: rename can import non-standard sources.
    stage4="$TMPDIR/stage4"
    manifest4=$(printf 'HEADER\trename-extra\t%s\tauto\nRENAME\trename-extra\tmcp.fragment.json\topencode.mcp.json\nEND\trename-extra\n' "$src")
    run_sync "$stage4" "$manifest4" >/dev/null
    assert_file "$stage4/rename-extra/opencode.mcp.json"

    # --- Test 5: explicit paths cherry-pick mode disables auto-discovery.
    stage5="$TMPDIR/stage5"
    manifest5=$(printf 'HEADER\texplicit\t%s\texplicit\nPATH\texplicit\tcommands/hello.md\tcommands/only.md\nPATH\texplicit\tpackage.json\tpackage.copy.json\nEND\texplicit\n' "$src")
    run_sync "$stage5" "$manifest5" >/dev/null
    assert_file "$stage5/explicit/commands/only.md"
    assert_file "$stage5/explicit/package.copy.json"
    assert_no_path "$stage5/explicit/skills/example-skill"
    assert_no_path "$stage5/explicit/package.json"

    # --- Test 6: paths + rename is a fatal mutual-exclusion error.
    stage6="$TMPDIR/stage6"
    manifest6=$(printf 'HEADER\tbad-mix\t%s\texplicit\nRENAME\tbad-mix\tmcp.fragment.json\topencode.mcp.json\nPATH\tbad-mix\tcommands/hello.md\tcommands/hello.md\nEND\tbad-mix\n' "$src")
    set +e
    output=$(run_sync "$stage6" "$manifest6" 2>&1)
    rc=$?
    set -e
    [ "$rc" -eq 1 ] || fail "paths+rename should exit 1, got $rc: $output"
    echo "$output" | grep -q 'sets both `paths` and `rename`' || fail "mutual exclusion warning missing: $output"

    # --- Test 7: destination traversal is rejected before copy/removal.
    stage7="$TMPDIR/stage7"
    manifest7=$(printf 'HEADER\tbad-dotdot\t%s\texplicit\nPATH\tbad-dotdot\tcommands/hello.md\t../escape.md\nEND\tbad-dotdot\n' "$src")
    set +e
    output=$(run_sync "$stage7" "$manifest7" 2>&1)
    rc=$?
    set -e
    [ "$rc" -eq 1 ] || fail "../ destination should exit 1, got $rc: $output"
    assert_no_path "$TMPDIR/escape.md"

    stage7b="$TMPDIR/stage7b"
    manifest7b=$(printf 'HEADER\tbad-abs\t%s\texplicit\nPATH\tbad-abs\tcommands/hello.md\t/abs.md\nEND\tbad-abs\n' "$src")
    set +e
    output=$(run_sync "$stage7b" "$manifest7b" 2>&1)
    rc=$?
    set -e
    [ "$rc" -eq 1 ] || fail "/abs destination should exit 1, got $rc: $output"

    stage7c="$TMPDIR/stage7c"
    manifest7c=$(printf 'HEADER\t../escape\t%s\tauto\nEND\t../escape\n' "$src")
    set +e
    output=$(run_sync "$stage7c" "$manifest7c" 2>&1)
    rc=$?
    set -e
    [ "$rc" -eq 1 ] || fail "../ import name should exit 1, got $rc: $output"
    assert_no_path "$TMPDIR/escape"

    # --- Test 8: explicit source traversal is rejected before staging.
    printf 'secret\n' > "$TMPDIR/secret.txt"
    stage8src="$TMPDIR/stage8src"
    manifest8src=$(printf 'HEADER\tbad-source\t%s\texplicit\nPATH\tbad-source\t../secret.txt\tcommands/leaked.md\nEND\tbad-source\n' "$src")
    set +e
    output=$(run_sync "$stage8src" "$manifest8src" 2>&1)
    rc=$?
    set -e
    [ "$rc" -eq 1 ] || fail "../ source should exit 1, got $rc: $output"
    echo "$output" | grep -q 'invalid source path' || fail "source traversal error missing: $output"
    assert_no_path "$stage8src/bad-source"

    # --- Test 9: unsupported ~user/ sources warn and skip.
    stage8="$TMPDIR/stage8"
    manifest8=$(printf 'HEADER\ttilde\t~other/repo\tauto\nEND\ttilde\n')
    output=$(run_sync "$stage8" "$manifest8" 2>&1)
    echo "$output" | grep -q 'uses unsupported ~user/ form' || fail "~user warning missing: $output"

    # --- Test 10: missing explicit source path warns but does not fail.
    stage9="$TMPDIR/stage9"
    manifest9=$(printf 'HEADER\tmissing\t%s\texplicit\nPATH\tmissing\tmissing.md\tcommands/missing.md\nEND\tmissing\n' "$src")
    output=$(run_sync "$stage9" "$manifest9" 2>&1)
    echo "$output" | grep -q 'missing path:' || fail "missing path warning missing: $output"

    # --- Test 11: re-run is idempotent and removes stale staging entries.
    stage10="$TMPDIR/stage10"
    manifest10=$(printf 'HEADER\tidem\t%s\tauto\nEND\tidem\n' "$src")
    run_sync "$stage10" "$manifest10" >/dev/null
    printf 'stale\n' > "$stage10/idem/stale.md"
    run_sync "$stage10" "$manifest10" >/dev/null
    assert_file "$stage10/idem/commands/hello.md"
    assert_no_path "$stage10/idem/stale.md"

    # --- Test 12: a staging failure preserves the last successful tree.
    stage11="$TMPDIR/stage11"
    run_sync "$stage11" "$manifest10" >/dev/null
    printf 'last-good\n' > "$stage11/idem/last-good.md"
    manifest11=$(printf 'HEADER\tbroken\t%s\texplicit\nPATH\tbroken\tcommands/hello.md\tcommands\nPATH\tbroken\tpackage.json\tcommands/nested.json\nEND\tbroken\n' "$src")
    set +e
    output=$(run_sync "$stage11" "$manifest11" 2>&1)
    rc=$?
    set -e
    [ "$rc" -ne 0 ] || fail "conflicting destinations should fail staging: $output"
    assert_file "$stage11/idem/last-good.md"
    assert_no_path "$stage11/broken"
    if compgen -G "$stage11.staging.*" >/dev/null; then
      fail "failed transaction left a staging directory"
    fi

    # --- Test 13: imports deleted from the manifest disappear on success.
    stage12="$TMPDIR/stage12"
    manifest12a=$(printf 'HEADER\tone\t%s\tauto\nEND\tone\nHEADER\ttwo\t%s\tauto\nEND\ttwo\n' "$src" "$src")
    manifest12b=$(printf 'HEADER\tone\t%s\tauto\nEND\tone\n' "$src")
    run_sync "$stage12" "$manifest12a" >/dev/null
    assert_file "$stage12/two/commands/hello.md"
    run_sync "$stage12" "$manifest12b" >/dev/null
    assert_file "$stage12/one/commands/hello.md"
    assert_no_path "$stage12/two"

    # --- Test 14: a successful empty manifest removes the previous tree.
    stage13="$TMPDIR/stage13"
    run_sync "$stage13" "$manifest10" >/dev/null
    assert_file "$stage13/idem/commands/hello.md"
    run_sync "$stage13" "" >/dev/null
    assert_no_path "$stage13"

    fault_bin="$TMPDIR/fault-bin"
    mkdir -p "$fault_bin"
    real_mktemp=$(command -v mktemp)
    real_mv=$(command -v mv)
    cat > "$fault_bin/mktemp" <<'EOF'
#!/bin/sh
count=0
[ ! -f "$FAULT_STATE.mktemp" ] || count=$(cat "$FAULT_STATE.mktemp")
count=$((count + 1))
printf '%s\n' "$count" > "$FAULT_STATE.mktemp"
if [ "$FAULT_MKTEMP" = "first" ] && [ "$count" -eq 1 ]; then exit 73; fi
if [ "$FAULT_MKTEMP" = "second" ] && [ "$count" -eq 2 ]; then exit 74; fi
exec "$REAL_MKTEMP" "$@"
EOF
    cat > "$fault_bin/mv" <<'EOF'
#!/bin/sh
count=0
[ ! -f "$FAULT_STATE.mv" ] || count=$(cat "$FAULT_STATE.mv")
count=$((count + 1))
printf '%s\n' "$count" > "$FAULT_STATE.mv"
if { [ "$FAULT_MV" = "publish" ] || [ "$FAULT_MV" = "publish-restore" ]; } && [ "$count" -eq 2 ]; then exit 75; fi
if [ "$FAULT_MV" = "publish-restore" ] && [ "$count" -eq 3 ]; then exit 76; fi
exec "$REAL_MV" "$@"
EOF
    chmod +x "$fault_bin/mktemp" "$fault_bin/mv"

    # --- Test 15: staging allocation failure is explicit and preserves old state.
    stage14="$TMPDIR/stage14"
    run_sync "$stage14" "$manifest10" >/dev/null
    printf 'last-good\n' > "$stage14/idem/last-good.md"
    fault_state="$TMPDIR/fault14" fault_mktemp=first fault_mv=""
    set +e
    output=$(run_sync_faulted "$stage14" "$manifest12b" 2>&1)
    rc=$?
    set -e
    [ "$rc" -ne 0 ] || fail "staging mktemp failure should fail"
    echo "$output" | grep -q 'failed to allocate OpenCode imports staging directory' || fail "staging allocation error missing: $output"
    assert_file "$stage14/idem/last-good.md"

    # --- Test 16: backup allocation failure removes staging and preserves old state.
    stage15="$TMPDIR/stage15"
    run_sync "$stage15" "$manifest10" >/dev/null
    printf 'last-good\n' > "$stage15/idem/last-good.md"
    fault_state="$TMPDIR/fault15" fault_mktemp=second fault_mv=""
    set +e
    output=$(run_sync_faulted "$stage15" "$manifest12b" 2>&1)
    rc=$?
    set -e
    [ "$rc" -ne 0 ] || fail "backup mktemp failure should fail"
    echo "$output" | grep -q 'failed to allocate OpenCode imports backup directory' || fail "backup allocation error missing: $output"
    assert_file "$stage15/idem/last-good.md"
    if compgen -G "$stage15.staging.*" >/dev/null; then fail "backup allocation failure left staging"; fi

    # --- Test 17: publication failure restores the previous successful tree.
    stage16="$TMPDIR/stage16"
    run_sync "$stage16" "$manifest10" >/dev/null
    printf 'last-good\n' > "$stage16/idem/last-good.md"
    fault_state="$TMPDIR/fault16" fault_mktemp="" fault_mv=publish
    set +e
    output=$(run_sync_faulted "$stage16" "$manifest12b" 2>&1)
    rc=$?
    set -e
    [ "$rc" -ne 0 ] || fail "publication failure should fail"
    assert_file "$stage16/idem/last-good.md"
    if compgen -G "$stage16.backup.*" >/dev/null; then fail "restored publication failure left backup"; fi

    # --- Test 18: failed restoration retains and reports the only good backup.
    stage17="$TMPDIR/stage17"
    run_sync "$stage17" "$manifest10" >/dev/null
    printf 'last-good\n' > "$stage17/idem/last-good.md"
    fault_state="$TMPDIR/fault17" fault_mktemp="" fault_mv=publish-restore
    set +e
    output=$(run_sync_faulted "$stage17" "$manifest12b" 2>&1)
    rc=$?
    set -e
    [ "$rc" -ne 0 ] || fail "publication+restore failure should fail"
    backup_line=$(printf '%s\n' "$output" | grep 'preserved backup at ')
    backup_path="''${backup_line##*preserved backup at }"
    [ -n "$backup_path" ] || fail "preserved backup path was not reported: $output"
    assert_file "$backup_path/idem/last-good.md"
    assert_no_path "$stage17"

    echo "all opencode-imports assertions passed"
    touch "$out"
  ''
