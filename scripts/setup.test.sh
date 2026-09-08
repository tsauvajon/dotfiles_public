set -eu

fail() { echo "FAIL: $*" >&2; exit 1; }

shim_dir="$TMPDIR/bin"
activation_out="$TMPDIR/activation"
mkdir -p "$shim_dir" "$activation_out"

cat > "$shim_dir/uname" <<'EOF'
#!/bin/sh
case "${1:-}" in
  -s) printf 'Darwin\n' ;;
  -m) printf 'arm64\n' ;;
  *) printf 'Darwin\n' ;;
esac
EOF

cat > "$shim_dir/nix" <<'EOF'
#!/bin/sh
case " $* " in
  *" eval "*)
    printf 'nix eval\n' >> "$SETUP_TEST_LOG"
    ;;
  *" build "*)
    printf 'nix build\n' >> "$SETUP_TEST_LOG"
    printf '%s\n' "$SETUP_TEST_ACTIVATION_OUT"
    ;;
  *)
    printf 'unexpected nix invocation: %s\n' "$*" >&2
    exit 99
    ;;
esac
EOF

cat > "$shim_dir/brew" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "shellenv" ]; then
  printf 'brew shellenv\n' >> "$SETUP_TEST_LOG"
  printf 'export HOMEBREW_SETUP_TEST=1\n'
  exit 0
fi
printf 'brew %s\n' "$*" >> "$SETUP_TEST_LOG"
EOF

cat > "$activation_out/activate" <<'EOF'
#!/bin/sh
printf 'activate\n' >> "$SETUP_TEST_LOG"
EOF
chmod +x "$shim_dir/uname" "$shim_dir/nix" "$shim_dir/brew" "$activation_out/activate"

make_repo() {
  local name="$1" repo="$TMPDIR/$name/repo"
  mkdir -p "$repo/scripts/lib" "$repo/config"
  install -m 0755 "$setup" "$repo/setup.sh"
  install -m 0644 "$importsHelper" "$repo/scripts/lib/opencode-imports.sh"
  printf 'cask "public-app"\n' > "$repo/config/Brewfile"
  cat > "$repo/scripts/bootstrap-keys.sh" <<'EOF'
#!/bin/sh
printf 'bootstrap-keys\n' >> "$SETUP_TEST_LOG"
EOF
  cat > "$repo/scripts/brew-cleanup.sh" <<'EOF'
#!/bin/sh
printf 'brew-cleanup %s\n' "$*" >> "$SETUP_TEST_LOG"
EOF
  chmod +x "$repo/scripts/bootstrap-keys.sh" "$repo/scripts/brew-cleanup.sh"
  printf '%s\n' "$repo"
}

prepare_home() {
  local name="$1"
  test_home="$TMPDIR/$name/home"
  log="$TMPDIR/$name/calls.log"
  mkdir -p "$test_home/.config/dotfiles" "$test_home/.config/dotfiles-managed"
  printf '{}\n' > "$test_home/.config/dotfiles/flake.nix"
  printf 'cask "personal-app"\n' > "$test_home/.config/dotfiles-managed/Brewfile.personal"
  mkdir -p "$test_home/.config/dotfiles/opencode-imports/stale"
  printf 'stale\n' > "$test_home/.config/dotfiles/opencode-imports/stale/file"
  : > "$log"
}

run_setup() {
  local repo="$1"
  shift
  set +e
  output=$(HOME="$test_home" \
    PATH="$shim_dir:$PATH" \
    SETUP_TEST_LOG="$log" \
    SETUP_TEST_ACTIVATION_OUT="$activation_out" \
    bash "$repo/setup.sh" "$@" 2>&1)
  rc=$?
  set -e
}

assert_log() {
  local expected="$1"
  printf '%s\n' "$expected" > "$TMPDIR/expected.log"
  diff -u "$TMPDIR/expected.log" "$log" || fail "unexpected orchestration log"
}

# Default: update, public bundle, build, activation, personal bundle, cleanup.
prepare_home default
repo=$(make_repo default)
run_setup "$repo"
[ "$rc" -eq 0 ] || fail "default setup failed ($rc): $output"
assert_log "brew shellenv
brew update
brew bundle install --file=$repo/config/Brewfile
nix eval
bootstrap-keys
nix build
activate
brew bundle install --file=$test_home/.config/dotfiles-managed/Brewfile.personal
brew-cleanup --apply"
[ ! -e "$test_home/.config/dotfiles/opencode-imports" ] || fail "empty imports manifest should remove stale staging"

# --no-brew-update skips only update and preserves all ordering/cleanup.
prepare_home no-update
repo=$(make_repo no-update)
run_setup "$repo" --no-brew-update
[ "$rc" -eq 0 ] || fail "--no-brew-update setup failed ($rc): $output"
assert_log "brew shellenv
brew bundle install --file=$repo/config/Brewfile
nix eval
bootstrap-keys
nix build
activate
brew bundle install --file=$test_home/.config/dotfiles-managed/Brewfile.personal
brew-cleanup --apply"
[ ! -e "$test_home/.config/dotfiles/opencode-imports" ] || fail "empty imports manifest should remove stale staging"

# Help succeeds, and invalid arguments fail with usage before orchestration.
prepare_home help
repo=$(make_repo help)
run_setup "$repo" --help
[ "$rc" -eq 0 ] || fail "--help should exit 0, got $rc: $output"
echo "$output" | grep -q '^Usage: setup.sh \[--no-brew-update\]$' || fail "help usage missing: $output"
[ ! -s "$log" ] || fail "--help should not run commands"

run_setup "$repo" --surprise
[ "$rc" -eq 2 ] || fail "invalid flag should exit 2, got $rc: $output"
echo "$output" | grep -q '^error: unknown argument: --surprise$' || fail "invalid flag error missing: $output"
echo "$output" | grep -q '^Usage: setup.sh \[--no-brew-update\]$' || fail "invalid flag usage missing: $output"
[ ! -s "$log" ] || fail "invalid flag should not run commands"

echo "all setup assertions passed"
touch "$out"
