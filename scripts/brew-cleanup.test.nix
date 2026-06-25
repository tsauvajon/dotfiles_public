# Integration test for scripts/brew-cleanup.sh.
{ pkgs, lib }:

let
  helper = ./brew-cleanup.sh;
in
pkgs.runCommand "brew-cleanup-test"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.diffutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    inherit helper;
  }
  ''
    set -eu

    fail() { echo "FAIL: $*" >&2; exit 1; }

    shim_dir="$TMPDIR/bin"
    mkdir -p "$shim_dir"

    cat > "$shim_dir/uname" <<'EOF'
#!/bin/sh
if [ "''${1:-}" = "-s" ]; then
  printf '%s\n' "''${UNAME_FAKE_SYSTEM:-Darwin}"
  exit 0
fi
printf '%s\n' "''${UNAME_FAKE_SYSTEM:-Darwin}"
EOF
    chmod +x "$shim_dir/uname"

    cat > "$shim_dir/brew" <<'EOF'
#!/bin/sh
if [ -n "''${BREW_FAKE_CALL_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$BREW_FAKE_CALL_LOG"
fi

if [ "$#" -eq 3 ] && [ "$1" = "list" ] && [ "$2" = "-1" ] && [ "$3" = "--cask" ]; then
  if [ -n "''${BREW_FAKE_INSTALLED:-}" ] && [ -f "$BREW_FAKE_INSTALLED" ]; then
    cat "$BREW_FAKE_INSTALLED"
  fi
  exit 0
fi

if [ "$#" -eq 3 ] && [ "$1" = "uninstall" ] && [ "$2" = "--cask" ]; then
  if [ -n "''${BREW_FAKE_LOG:-}" ]; then
    printf 'uninstall --cask %s\n' "$3" >> "$BREW_FAKE_LOG"
  fi
  exit "''${BREW_FAKE_UNINSTALL_RC:-0}"
fi

printf 'unexpected brew invocation: %s\n' "$*" >&2
exit 99
EOF
    chmod +x "$shim_dir/brew"

    make_repo() {
      local name="$1"
      local repo="$TMPDIR/$name/fakerepo"
      mkdir -p "$repo/scripts" "$repo/config"
      install -m 0755 "$helper" "$repo/scripts/brew-cleanup.sh"
      printf '%s\n' "$repo"
    }

    reset_case_env() {
      local name="$1"
      test_home="$TMPDIR/$name/home"
      installed_file="$TMPDIR/$name/installed"
      uninstall_log="$TMPDIR/$name/uninstall.log"
      call_log="$TMPDIR/$name/calls.log"
      fake_system=Darwin
      uninstall_rc=0
      rm -rf "$TMPDIR/$name"
      mkdir -p "$test_home"
      : > "$installed_file"
      rm -f "$uninstall_log" "$call_log"
    }

    write_public_brewfile() {
      local repo="$1"
      cat > "$repo/config/Brewfile"
    }

    write_personal_brewfile() {
      mkdir -p "$test_home/.config/dotfiles-managed"
      cat > "$test_home/.config/dotfiles-managed/Brewfile.personal"
    }

    run_cleanup() {
      local repo="$1"
      shift
      set +e
      output=$(HOME="$test_home" \
        PATH="$shim_dir:$PATH" \
        UNAME_FAKE_SYSTEM="$fake_system" \
        BREW_FAKE_INSTALLED="$installed_file" \
        BREW_FAKE_LOG="$uninstall_log" \
        BREW_FAKE_CALL_LOG="$call_log" \
        BREW_FAKE_UNINSTALL_RC="$uninstall_rc" \
        bash "$repo/scripts/brew-cleanup.sh" "$@" 2>&1)
      rc=$?
      set -e
    }

    assert_output_contains() {
      echo "$output" | grep -q "$1" || fail "$2: $output"
    }

    assert_output_not_contains() {
      ! echo "$output" | grep -q "$1" || fail "$2: $output"
    }

    assert_no_uninstalls() {
      [ ! -s "$uninstall_log" ] || fail "expected no uninstalls, got: $(cat "$uninstall_log")"
    }

    assert_uninstall_log() {
      local expected="$1"
      printf '%s\n' "$expected" > "$TMPDIR/expected-uninstall-log"
      diff -u "$TMPDIR/expected-uninstall-log" "$uninstall_log" \
        || fail "unexpected uninstall log"
    }

    # --- Test 1: default dry-run computes extras across public + personal Brewfiles.
    reset_case_env case1
    repo=$(make_repo case1)
    write_public_brewfile "$repo" <<'EOF'
tap "homebrew/bundle"
brew "ripgrep"
cask "a"
EOF
    write_personal_brewfile <<'EOF'
brew "fd"
cask "b"
EOF
    printf 'a\nb\nc\nd\n' > "$installed_file"
    run_cleanup "$repo"
    [ "$rc" -eq 0 ] || fail "default dry-run should exit 0, got $rc: $output"
    assert_output_contains '^Extra Homebrew casks not declared in any managed Brewfile:$' "default dry-run header missing"
    assert_output_contains '^  c$' "default dry-run should print c"
    assert_output_contains '^  d$' "default dry-run should print d"
    assert_output_not_contains '^  a$' "default dry-run should not print wanted public cask"
    assert_output_not_contains '^  b$' "default dry-run should not print wanted personal cask"
    assert_output_contains 'Dry run only\. Pass --apply to uninstall these casks\.' "default dry-run notice missing"
    assert_no_uninstalls

    # --- Test 2: explicit --dry-run behaves like the default dry-run.
    reset_case_env case2
    repo=$(make_repo case2)
    write_public_brewfile "$repo" <<'EOF'
tap "homebrew/bundle"
brew "ripgrep"
cask "a"
EOF
    write_personal_brewfile <<'EOF'
brew "fd"
cask "b"
EOF
    printf 'a\nb\nc\nd\n' > "$installed_file"
    run_cleanup "$repo" --dry-run
    [ "$rc" -eq 0 ] || fail "explicit dry-run should exit 0, got $rc: $output"
    assert_output_contains '^  c$' "explicit dry-run should print c"
    assert_output_contains '^  d$' "explicit dry-run should print d"
    assert_output_contains 'Dry run only\. Pass --apply to uninstall these casks\.' "explicit dry-run notice missing"
    assert_no_uninstalls

    # --- Test 3: --apply uninstalls exactly the extra casks in sorted order.
    reset_case_env case3
    repo=$(make_repo case3)
    write_public_brewfile "$repo" <<'EOF'
brew "c"
cask "a"
EOF
    write_personal_brewfile <<'EOF'
cask "b"
EOF
    printf 'a\nb\nc\nd\n' > "$installed_file"
    run_cleanup "$repo" --apply
    [ "$rc" -eq 0 ] || fail "apply should exit 0, got $rc: $output"
    assert_uninstall_log 'uninstall --cask c
uninstall --cask d'

    # --- Test 4: no extras is a no-op with a success message.
    reset_case_env case4
    repo=$(make_repo case4)
    write_public_brewfile "$repo" <<'EOF'
cask "a"
cask "b"
EOF
    printf 'a\n' > "$installed_file"
    run_cleanup "$repo" --apply
    [ "$rc" -eq 0 ] || fail "no extras should exit 0, got $rc: $output"
    assert_output_contains '^No extra Homebrew casks found\.$' "no extras message missing"
    assert_no_uninstalls

    # --- Test 5: empty wanted set + --apply intentionally removes every installed cask.
    reset_case_env case5
    repo=$(make_repo case5)
    write_public_brewfile "$repo" <<'EOF'
tap "homebrew/bundle"
brew "ripgrep"
EOF
    write_personal_brewfile <<'EOF'
brew "fd"
EOF
    printf 'b\na\nc\n' > "$installed_file"
    run_cleanup "$repo" --apply
    [ "$rc" -eq 0 ] || fail "empty wanted apply should exit 0, got $rc: $output"
    assert_uninstall_log 'uninstall --cask a
uninstall --cask b
uninstall --cask c'

    # --- Test 6: missing public Brewfile is fatal and reports the derived path.
    reset_case_env case6
    repo=$(make_repo case6)
    rm -f "$repo/config/Brewfile"
    run_cleanup "$repo"
    [ "$rc" -eq 1 ] || fail "missing public Brewfile should exit 1, got $rc: $output"
    assert_output_contains "error: Brewfile not found: $repo/config/Brewfile" "missing Brewfile path missing"
    [ ! -s "$call_log" ] || fail "missing Brewfile should not call brew: $(cat "$call_log")"

    # --- Test 7: non-Darwin platforms are a no-op before any brew calls.
    reset_case_env case7
    repo=$(make_repo case7)
    rm -f "$repo/config/Brewfile"
    fake_system=Linux
    run_cleanup "$repo" --apply
    [ "$rc" -eq 0 ] || fail "non-Darwin should exit 0, got $rc: $output"
    assert_output_contains '^Homebrew cleanup is only supported on macOS\.$' "non-Darwin message missing"
    [ ! -s "$call_log" ] || fail "non-Darwin should not call brew: $(cat "$call_log")"
    assert_no_uninstalls

    # --- Test 8: unknown flags fail with usage on stderr.
    reset_case_env case8
    repo=$(make_repo case8)
    run_cleanup "$repo" --surprise
    [ "$rc" -eq 2 ] || fail "unknown flag should exit 2, got $rc: $output"
    assert_output_contains '^error: unknown argument: --surprise$' "unknown flag error missing"
    assert_output_contains '^Usage: scripts/brew-cleanup\.sh \[--apply\]$' "usage missing for unknown flag"

    # --- Test 9: brew uninstall failure aborts after the first extra cask.
    reset_case_env case9
    repo=$(make_repo case9)
    write_public_brewfile "$repo" <<'EOF'
cask "a"
EOF
    printf 'a\nc\nd\n' > "$installed_file"
    uninstall_rc=1
    run_cleanup "$repo" --apply
    [ "$rc" -eq 1 ] || fail "uninstall failure should exit 1, got $rc: $output"
    assert_uninstall_log 'uninstall --cask c'

    echo "all brew-cleanup assertions passed"
    touch "$out"
  ''
