# Integration test for scripts/nixgl-nvidia-doctor.sh.
{ pkgs, lib }:

let
  helper = ./nixgl-nvidia-doctor.sh;
in
pkgs.runCommand "nixgl-nvidia-doctor-test"
  {
    nativeBuildInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    inherit helper;
  }
  ''
        set -eu

        fail() { echo "FAIL: $*" >&2; exit 1; }

        config_for() {
          local file="$1"
          local version="$2"
          cat > "$file" <<EOF
    {
      _module.args.nixglNvidiaVersion = "$version";
    }
    EOF
        }

        good_config="$TMPDIR/linux-good.nix"
        old_config="$TMPDIR/linux-old.nix"
        empty_config="$TMPDIR/linux-empty.nix"
        config_for "$good_config" 610.43.02
        config_for "$old_config" 595.71.05
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
        echo "$output" | grep -q 'ERROR: could not read nixglNvidiaVersion' \
          || fail "missing configured version should print ERROR: $output"

        echo "all nixgl-nvidia-doctor assertions passed"
        touch "$out"
  ''
