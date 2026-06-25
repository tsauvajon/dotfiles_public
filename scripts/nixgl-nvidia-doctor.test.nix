# Integration test for scripts/nixgl-nvidia-doctor.sh.
{ pkgs, lib }:

let
  helper = ./nixgl-nvidia-doctor.sh;
  wrapperStoreRef = pkgs.writeText "nvidia-x11-610.43.02-driver-ref" ''
    /nix/store/00000000000000000000000000000000-nvidia-x11-610.43.02-nixGL
  '';
in
pkgs.runCommand "nixgl-nvidia-doctor-test"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    inherit helper wrapperStoreRef;
  }
  ''
        set -eu

        fail() { echo "FAIL: $*" >&2; exit 1; }

        multiline_config_for() {
          local file="$1"
          local version="$2"
          cat > "$file" <<EOF
    # Per-host config for Thomas's Linux machine(s).
    { ... }:

    {
      programs.fish.enable = true;

      # NVIDIA driver pin for nixGL. The hash is the sha256 of
      # NVIDIA-Linux-x86_64-<version>.run, which lets nixGL build the driver via
      # \`fetchurl\` (pure) instead of \`builtins.fetchurl\` (impure). Update \`version\`
      # and \`hash\` together from the same driver release.
      _module.args.nixglNvidia = {
        version = "$version";
        hash = "sha256-MDSgVLtM33dS/43CclZMsQVROAS/9TU4lFkBsWyndGM=";
      };
    }
    EOF
        }

        single_line_config_for() {
          local file="$1"
          local version="$2"
          cat > "$file" <<EOF
    {
      _module.args.nixglNvidia = { version = "$version"; hash = "sha256-MDSgVLtM33dS/43CclZMsQVROAS/9TU4lFkBsWyndGM="; };
    }
    EOF
        }

        hash_first_config_for() {
          local file="$1"
          local version="$2"
          cat > "$file" <<EOF
    {
      _module.args.nixglNvidia = {
        hash = "sha256-MDSgVLtM33dS/43CclZMsQVROAS/9TU4lFkBsWyndGM=";
        version = "$version";
      };
    }
    EOF
        }

        good_config="$TMPDIR/linux-good.nix"
        single_line_config="$TMPDIR/linux-single-line.nix"
        hash_first_config="$TMPDIR/linux-hash-first.nix"
        old_config="$TMPDIR/linux-old.nix"
        empty_config="$TMPDIR/linux-empty.nix"
        multiline_config_for "$good_config" 610.43.02
        single_line_config_for "$single_line_config" 610.43.02
        hash_first_config_for "$hash_first_config" 610.43.02
        multiline_config_for "$old_config" 595.71.05
        : > "$empty_config"

        set +e
        output=$(NIXGL_NVIDIA_CONFIG_FILE="$good_config" \
          NIXGL_NVIDIA_RUNNING_VERSION=610.43.02 \
          NIXGL_NVIDIA_WRAPPER_VERSION=610.43.02 \
          bash "$helper" 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 0 ] || fail "matching versions should exit 0, got $rc: $output"
        echo "$output" | grep -q '^OK: nixGL NVIDIA pin matches the running driver\.$' \
          || fail "matching versions should print OK: $output"

        set +e
        output=$(NIXGL_NVIDIA_CONFIG_FILE="$single_line_config" \
          NIXGL_NVIDIA_RUNNING_VERSION=610.43.02 \
          NIXGL_NVIDIA_WRAPPER_VERSION=610.43.02 \
          bash "$helper" 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 0 ] || fail "single-line nixglNvidia attrset should exit 0, got $rc: $output"
        echo "$output" | grep -q '^configured nixGL NVIDIA: 610\.43\.02$' \
          || fail "single-line nixglNvidia attrset should parse configured version: $output"

        set +e
        output=$(NIXGL_NVIDIA_CONFIG_FILE="$hash_first_config" \
          NIXGL_NVIDIA_RUNNING_VERSION=610.43.02 \
          NIXGL_NVIDIA_WRAPPER_VERSION=610.43.02 \
          bash "$helper" 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 0 ] || fail "hash-first nixglNvidia attrset should exit 0, got $rc: $output"
        echo "$output" | grep -q '^configured nixGL NVIDIA: 610\.43\.02$' \
          || fail "hash-first nixglNvidia attrset should parse configured version: $output"

        wrapper_bin="$TMPDIR/bin"
        mkdir -p "$wrapper_bin"
        cat > "$wrapper_bin/fake-wrapper" <<EOF
    #!/usr/bin/env bash
    exec "$wrapperStoreRef" "\$@"
    EOF
        chmod +x "$wrapper_bin/fake-wrapper"

        set +e
        output=$(PATH="$wrapper_bin:$PATH" \
          NIXGL_NVIDIA_CONFIG_FILE="$good_config" \
          NIXGL_NVIDIA_RUNNING_VERSION=610.43.02 \
          NIXGL_NVIDIA_WRAPPER_COMMANDS=fake-wrapper \
          bash "$helper" 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 0 ] || fail "wrapper store-ref discovery should exit 0, got $rc: $output"
        echo "$output" | grep -q '^active nixGL wrapper:    610.43.02 (fake-wrapper)$' \
          || fail "wrapper store-ref discovery should identify fake-wrapper version: $output"

        set +e
        output=$(NIXGL_NVIDIA_CONFIG_FILE="$old_config" \
          NIXGL_NVIDIA_RUNNING_VERSION=610.43.02 \
          NIXGL_NVIDIA_WRAPPER_VERSION=595.71.05 \
          bash "$helper" 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 1 ] || fail "driver mismatch should exit 1, got $rc: $output"
        echo "$output" | grep -q 'MISMATCH: running driver is 610.43.02, but nixGL is configured for 595.71.05\.' \
          || fail "driver mismatch message missing: $output"
        echo "$output" | grep -q 'scripts/nvidia-driver-hash.sh 610.43.02' \
          || fail "driver mismatch should include hash helper hint: $output"

        set +e
        output=$(NIXGL_NVIDIA_CONFIG_FILE="$good_config" \
          NIXGL_NVIDIA_RUNNING_VERSION=610.43.02 \
          NIXGL_NVIDIA_WRAPPER_VERSION=595.71.05 \
          bash "$helper" 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 1 ] || fail "active wrapper mismatch should exit 1, got $rc: $output"
        echo "$output" | grep -q 'active wrapper uses 595.71.05' \
          || fail "active wrapper mismatch message missing: $output"

        set +e
        output=$(NIXGL_NVIDIA_CONFIG_FILE="$good_config" \
          NIXGL_NVIDIA_RUNNING_VERSION= \
          NIXGL_NVIDIA_WRAPPER_VERSION=610.43.02 \
          bash "$helper" 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 0 ] || fail "missing running driver should be non-fatal, got $rc: $output"
        echo "$output" | grep -q '^UNKNOWN: no running NVIDIA driver detected\. Nothing to compare\.$' \
          || fail "missing driver should print UNKNOWN: $output"

        set +e
        output=$(NIXGL_NVIDIA_CONFIG_FILE="$empty_config" \
          NIXGL_NVIDIA_RUNNING_VERSION=610.43.02 \
          NIXGL_NVIDIA_WRAPPER_VERSION=610.43.02 \
          bash "$helper" 2>&1)
        rc=$?
        set -e
        [ "$rc" -eq 1 ] || fail "missing configured version should exit 1, got $rc: $output"
        echo "$output" | grep -q 'ERROR: could not read nixglNvidia.version' \
          || fail "missing configured version should print ERROR: $output"

        echo "all nixgl-nvidia-doctor assertions passed"
        touch "$out"
  ''
