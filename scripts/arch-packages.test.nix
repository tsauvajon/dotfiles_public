# Integration test for scripts/arch-packages.sh.
{ pkgs, lib }:

let
  helper = ./arch-packages.sh;
in
pkgs.runCommand "arch-packages-test"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.diffutils
      pkgs.gnugrep
    ];
    inherit helper;
  }
  ''
    set -eu

    fail() { echo "FAIL: $*" >&2; exit 1; }

    make_repo() {
      local name="$1"
      local repo="$TMPDIR/$name/fakerepo"
      mkdir -p "$repo/scripts" "$repo/packages/arch"
      install -m 0755 "$helper" "$repo/scripts/arch-packages.sh"
      cat > "$repo/packages/arch/pacman.txt" <<'EOF'
    # Official packages

    qpdf # required by CUPS filters
      # indented comment
    EOF
      printf '%s\n' "$repo"
    }

    make_shims() {
      shim_dir="$TMPDIR/bin"
      mkdir -p "$shim_dir"

      cat > "$shim_dir/pacman" <<'EOF'
    #!/bin/sh
    set -eu

    if [ "$#" -eq 2 ] && [ "$1" = "-Qi" ]; then
      package="$2"
      if [ -n "''${PACMAN_FAKE_INSTALLED:-}" ] && grep -qx -- "$package" "$PACMAN_FAKE_INSTALLED"; then
        exit 0
      fi
      exit 1
    fi

    if [ "$#" -ge 3 ] && [ "$1" = "-S" ] && [ "$2" = "--needed" ]; then
      if [ -n "''${PACMAN_FAKE_LOG:-}" ]; then
        printf 'pacman'
        for arg in "$@"; do printf ' %s' "$arg"; done
        printf '\n'
      fi >> "$PACMAN_FAKE_LOG"
      exit 0
    fi

    printf 'unexpected pacman invocation: %s\n' "$*" >&2
    exit 99
    EOF
      chmod +x "$shim_dir/pacman"

      cat > "$shim_dir/sudo" <<'EOF'
    #!/bin/sh
    set -eu
    exec "$@"
    EOF
      chmod +x "$shim_dir/sudo"

      cat > "$shim_dir/id" <<'EOF'
    #!/bin/sh
    if [ "''${1:-}" = "-u" ]; then
      printf '1000\n'
      exit 0
    fi
    exit 99
    EOF
      chmod +x "$shim_dir/id"
    }

    run_arch_packages() {
      local repo="$1"
      shift
      set +e
      output=$(PATH="$shim_dir:$PATH" \
        PACMAN_FAKE_INSTALLED="$installed_file" \
        PACMAN_FAKE_LOG="$install_log" \
        bash "$repo/scripts/arch-packages.sh" "$@" 2>&1)
      rc=$?
      set -e
    }

    assert_output_contains() {
      echo "$output" | grep -q -- "$1" || fail "$2: $output"
    }

    make_shims

    # --- Test 1: no pacman is a no-op.
    repo=$(make_repo case1)
    set +e
    output=$(PATH="${pkgs.coreutils}/bin" ${pkgs.bash}/bin/bash "$repo/scripts/arch-packages.sh" 2>&1)
    rc=$?
    set -e
    [ "$rc" -eq 0 ] || fail "missing pacman should exit 0, got $rc: $output"
    assert_output_contains '^pacman not found; skipping managed Arch packages\.$' "missing pacman message missing"

    # --- Test 2: --check reports missing packages and exits 1.
    repo=$(make_repo case2)
    installed_file="$TMPDIR/case2/installed"
    install_log="$TMPDIR/case2/install.log"
    mkdir -p "$TMPDIR/case2"
    : > "$installed_file"
    : > "$install_log"
    run_arch_packages "$repo" --check
    [ "$rc" -eq 1 ] || fail "--check with missing packages should exit 1, got $rc: $output"
    assert_output_contains '^Missing managed Arch packages:$' "missing package header missing"
    assert_output_contains '^  qpdf$' "qpdf missing line missing"
    [ ! -s "$install_log" ] || fail "--check should not install: $(cat "$install_log")"

    # --- Test 3: --install installs only missing packages through sudo pacman.
    repo=$(make_repo case3)
    installed_file="$TMPDIR/case3/installed"
    install_log="$TMPDIR/case3/install.log"
    mkdir -p "$TMPDIR/case3"
    : > "$installed_file"
    : > "$install_log"
    run_arch_packages "$repo" --install
    [ "$rc" -eq 0 ] || fail "--install should exit 0, got $rc: $output"
    printf '%s\n' 'pacman -S --needed qpdf' > "$TMPDIR/expected-install.log"
    diff -u "$TMPDIR/expected-install.log" "$install_log" || fail "unexpected install log"

    # --- Test 4: installed packages are a no-op and do not call sudo/pacman -S.
    repo=$(make_repo case4)
    installed_file="$TMPDIR/case4/installed"
    install_log="$TMPDIR/case4/install.log"
    mkdir -p "$TMPDIR/case4"
    printf '%s\n' qpdf > "$installed_file"
    : > "$install_log"
    run_arch_packages "$repo"
    [ "$rc" -eq 0 ] || fail "installed packages should exit 0, got $rc: $output"
    assert_output_contains '^All managed Arch packages are installed\.$' "all installed message missing"
    [ ! -s "$install_log" ] || fail "installed packages should not be installed again: $(cat "$install_log")"

    touch "$out"
  ''
