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

    echo "all opencode-imports assertions passed"
    touch "$out"
  ''
