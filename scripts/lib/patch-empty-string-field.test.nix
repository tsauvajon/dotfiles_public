# Integration test for scripts/lib/patch-empty-string-field.sh.
#
# The helper is plain shell that mutates a Nix file in place. We can
# only observe its effects by running it against fixture files and
# diffing the result, so the test wraps the helper in a `runCommand`
# and walks several scenarios. Exits non-zero on the first failed
# assertion (set -e), and exits 0 + writes $out when all assertions
# pass.
#
# Wired into the flake's `checks.${system}.patch-string-field-test`.
{ pkgs, lib }:

let
  helper = ./patch-empty-string-field.sh;
  fixtureEmpty = ./patch-empty-string-field.test/flake-empty.nix;
  fixtureNull = ./patch-empty-string-field.test/flake-null.nix;
  fixtureAbsent = ./patch-empty-string-field.test/flake-absent.nix;
in
pkgs.runCommand "patch-string-field-test"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.gnused
      pkgs.gnugrep
      pkgs.coreutils
    ];
    inherit
      helper
      fixtureEmpty
      fixtureNull
      fixtureAbsent
      ;
  }
  ''
    set -eu

    fail() { echo "FAIL: $*" >&2; exit 1; }

    # Stable HOME inside the build sandbox in case the helper ever
    # touches it (it does not today, but cheap insurance).
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"

    expected_field_line() {
      # Build the expected single-line Nix assignment for assertions.
      # Mirrors the indentation in flake-empty.nix.
      local field="$1"
      local value="$2"
      printf '      %s = "%s";' "$field" "$value"
    }

    grep_field() {
      grep -E "^[[:space:]]*$2[[:space:]]*=" "$1" | head -n1 || true
    }

    # --- Test 1: empty literal -> patched, exit 0 --------------------
    fix1="$TMPDIR/test1.nix"
    install -m 0644 "$fixtureEmpty" "$fix1"
    bash "$helper" "$fix1" name "Thomas" >/dev/null \
      || fail "test1: helper failed on empty literal"
    line=$(grep_field "$fix1" name)
    expected=$(expected_field_line name "Thomas")
    [ "$line" = "$expected" ] \
      || fail "test1: expected '$expected', got: '$line'"

    # --- Test 2: idempotent re-run -----------------------------------
    bash "$helper" "$fix1" name "Thomas" >/dev/null \
      || fail "test2: idempotent re-run should succeed"
    line=$(grep_field "$fix1" name)
    [ "$line" = "$expected" ] \
      || fail "test2: file should be unchanged after idempotent re-run, got: '$line'"

    # --- Test 3: already-set, different value -> exit 2 --------------
    set +e
    bash "$helper" "$fix1" name "Other" 2>/dev/null
    rc=$?
    set -e
    [ "$rc" -eq 2 ] || fail "test3: expected exit 2 on conflict, got $rc"
    line=$(grep_field "$fix1" name)
    [ "$line" = "$expected" ] \
      || fail "test3: file should not be overwritten on conflict, got: '$line'"

    # --- Test 4: missing flake file -> exit 4 ------------------------
    set +e
    bash "$helper" "$TMPDIR/does-not-exist.nix" name "Thomas" 2>/dev/null
    rc=$?
    set -e
    [ "$rc" -eq 4 ] || fail "test4: expected exit 4 on missing file, got $rc"

    # --- Test 5: non-empty-literal form (null) -> exit 3 -------------
    fix5="$TMPDIR/test5.nix"
    install -m 0644 "$fixtureNull" "$fix5"
    set +e
    bash "$helper" "$fix5" name "Thomas" 2>/dev/null
    rc=$?
    set -e
    [ "$rc" -eq 3 ] || fail "test5: expected exit 3 on null form, got $rc"
    grep -q 'name = null;' "$fix5" \
      || fail "test5: null form should not be modified"

    # --- Test 6: special chars (/ and &) splice cleanly --------------
    fix6="$TMPDIR/test6.nix"
    install -m 0644 "$fixtureEmpty" "$fix6"
    bash "$helper" "$fix6" signingKey "abc/def&ghi" >/dev/null \
      || fail "test6: helper failed on special chars"
    line=$(grep_field "$fix6" signingKey)
    expected6=$(expected_field_line signingKey "abc/def&ghi")
    [ "$line" = "$expected6" ] \
      || fail "test6: expected '$expected6', got: '$line'"

    # --- Test 7: bad usage (wrong arg count) -> exit 64 --------------
    set +e
    bash "$helper" only-one-arg 2>/dev/null
    rc=$?
    set -e
    [ "$rc" -eq 64 ] || fail "test7: expected exit 64 on bad usage, got $rc"

    # --- Test 8: empty value -> exit 64 ------------------------------
    set +e
    bash "$helper" "$fix1" name "" 2>/dev/null
    rc=$?
    set -e
    [ "$rc" -eq 64 ] || fail "test8: expected exit 64 on empty value, got $rc"

    # --- Test 9: field absent entirely -> exit 5 ---------------------
    # The "absent" fixture omits `name` and `signingKey` but defines
    # `email`. Patching the missing fields exits 5; the present field
    # behaves like the matching shape (set to a non-empty value).
    fix9="$TMPDIR/test9.nix"
    install -m 0644 "$fixtureAbsent" "$fix9"
    set +e
    bash "$helper" "$fix9" name "Thomas" 2>/dev/null
    rc=$?
    set -e
    [ "$rc" -eq 5 ] || fail "test9: expected exit 5 on absent field, got $rc"
    grep -q 'name' "$fix9" \
      && fail "test9: absent field should not be added to the file"
    set +e
    bash "$helper" "$fix9" signingKey "ABCDEF" 2>/dev/null
    rc=$?
    set -e
    [ "$rc" -eq 5 ] || fail "test9: expected exit 5 on absent signingKey, got $rc"

    # --- Test 10: present field with non-empty literal -> exit 2 -----
    # The "absent" fixture also exercises a present field set to a
    # different value. This must continue to exit 2 (not 5).
    set +e
    bash "$helper" "$fix9" email "other@example.com" 2>/dev/null
    rc=$?
    set -e
    [ "$rc" -eq 2 ] || fail "test10: expected exit 2 on present-different value, got $rc"

    echo "all patch-string-field assertions passed"
    touch "$out"
  ''
