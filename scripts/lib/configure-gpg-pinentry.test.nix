# Integration test for scripts/lib/configure-gpg-pinentry.sh.
#
# Wraps the helper in a `runCommand` and walks several conf shapes:
# missing file, empty file, single pinentry line, multiple pinentry
# lines, and conf with unrelated settings to preserve. Exits non-zero
# on the first failed assertion.
#
# Wired into the flake's `checks.${system}.configure-gpg-pinentry-test`.
{ pkgs, lib }:

let
  helper = ./configure-gpg-pinentry.sh;
in
pkgs.runCommand "configure-gpg-pinentry-test"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.gnugrep
      pkgs.coreutils
    ];
    inherit helper;
  }
  ''
    set -eu

    fail() { echo "FAIL: $*" >&2; exit 1; }

    PINENTRY="/nix/store/fake-pinentry-mac/bin/pinentry-mac"
    EXPECTED_LINE="pinentry-program $PINENTRY"

    # --- Test 1: missing file -> creates with single line ----------
    f1="$TMPDIR/t1/gpg-agent.conf"
    bash "$helper" "$f1" "$PINENTRY"
    [ -f "$f1" ] || fail "test1: file not created"
    [ "$(cat "$f1")" = "$EXPECTED_LINE" ] \
      || fail "test1: expected single line '$EXPECTED_LINE', got: $(cat "$f1")"

    # --- Test 2: empty existing file -> single line ----------------
    f2="$TMPDIR/t2/gpg-agent.conf"
    mkdir -p "$(dirname "$f2")"
    : > "$f2"
    bash "$helper" "$f2" "$PINENTRY"
    [ "$(cat "$f2")" = "$EXPECTED_LINE" ] \
      || fail "test2: expected single line, got: $(cat "$f2")"

    # --- Test 3: existing single pinentry line replaced ------------
    f3="$TMPDIR/t3/gpg-agent.conf"
    mkdir -p "$(dirname "$f3")"
    printf 'pinentry-program /old/path/pinentry\n' > "$f3"
    bash "$helper" "$f3" "$PINENTRY"
    count=$(grep -c '^pinentry-program ' "$f3")
    [ "$count" = "1" ] || fail "test3: expected exactly 1 pinentry line, got $count"
    grep -q "^$EXPECTED_LINE\$" "$f3" \
      || fail "test3: missing expected line: $(cat "$f3")"

    # --- Test 4: multiple pinentry lines deduplicated --------------
    f4="$TMPDIR/t4/gpg-agent.conf"
    mkdir -p "$(dirname "$f4")"
    printf 'pinentry-program /a\npinentry-program /b\npinentry-program /c\n' > "$f4"
    bash "$helper" "$f4" "$PINENTRY"
    count=$(grep -c '^pinentry-program ' "$f4")
    [ "$count" = "1" ] || fail "test4: expected dedup to 1 line, got $count"
    grep -q "^$EXPECTED_LINE\$" "$f4" || fail "test4: missing expected line"

    # --- Test 5: unrelated settings preserved ----------------------
    f5="$TMPDIR/t5/gpg-agent.conf"
    mkdir -p "$(dirname "$f5")"
    printf 'default-cache-ttl 600\nmax-cache-ttl 7200\npinentry-program /old\n' > "$f5"
    bash "$helper" "$f5" "$PINENTRY"
    grep -q '^default-cache-ttl 600$' "$f5" || fail "test5: lost default-cache-ttl"
    grep -q '^max-cache-ttl 7200$' "$f5" || fail "test5: lost max-cache-ttl"
    count=$(grep -c '^pinentry-program ' "$f5")
    [ "$count" = "1" ] || fail "test5: expected 1 pinentry line, got $count"
    grep -q "^$EXPECTED_LINE\$" "$f5" || fail "test5: missing expected line"

    # --- Test 6: idempotent re-run does not grow the file ----------
    bash "$helper" "$f5" "$PINENTRY"
    count=$(grep -c '^pinentry-program ' "$f5")
    [ "$count" = "1" ] || fail "test6: idempotent re-run grew the file"

    # --- Test 7: switching pinentry program updates the line -------
    NEW_PINENTRY="/nix/store/different-pinentry/bin/pinentry-curses"
    bash "$helper" "$f5" "$NEW_PINENTRY"
    count=$(grep -c '^pinentry-program ' "$f5")
    [ "$count" = "1" ] || fail "test7: expected 1 pinentry line after switch, got $count"
    grep -q "^pinentry-program $NEW_PINENTRY\$" "$f5" \
      || fail "test7: pinentry program not updated: $(cat "$f5")"

    # --- Test 8: bad usage (wrong arg count) -> exit 64 ------------
    set +e
    bash "$helper" only-one-arg 2>/dev/null
    rc=$?
    set -e
    [ "$rc" -eq 64 ] || fail "test8: expected exit 64 on bad usage, got $rc"

    # --- Test 9: empty arg -> exit 64 ------------------------------
    set +e
    bash "$helper" "" "$PINENTRY" 2>/dev/null
    rc=$?
    set -e
    [ "$rc" -eq 64 ] || fail "test9: expected exit 64 on empty conf path, got $rc"

    # --- Test 10: non-store symlink replaced cleanly --------------
    # We cannot create a /nix/store/-prefixed path in the sandbox, so
    # we exercise only the regular-file path. The store-symlink branch
    # is small (`rm -f` on detect) and the rewrite logic that follows
    # is identical, so test 5/6 cover it transitively.
    f10="$TMPDIR/t10/gpg-agent.conf"
    mkdir -p "$(dirname "$f10")"
    real="$TMPDIR/t10/real.conf"
    printf 'default-cache-ttl 1234\npinentry-program /old\n' > "$real"
    ln -s "$real" "$f10"
    bash "$helper" "$f10" "$PINENTRY"
    grep -q '^default-cache-ttl 1234$' "$f10" || fail "test10: lost setting through symlink"
    grep -q "^$EXPECTED_LINE\$" "$f10" || fail "test10: missing expected line"

    echo "all configure-gpg-pinentry assertions passed"
    touch "$out"
  ''
