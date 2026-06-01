#!/usr/bin/env bash
# Diagnose mismatches between the running NVIDIA driver and nixGL's pin.
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
usage: nixgl-nvidia-doctor.sh

Checks:
  - running NVIDIA kernel driver version
  - configured nixglNvidiaVersion in home/hosts/linux.nix
  - active nixGL wrapper version, when discoverable from kitty/alacritty

Test/advanced overrides:
  NIXGL_NVIDIA_CONFIG_FILE
  NIXGL_NVIDIA_RUNNING_VERSION
  NIXGL_NVIDIA_WRAPPER_VERSION
  NIXGL_NVIDIA_WRAPPER_COMMANDS
EOF
}

if [[ $# -gt 0 ]]; then
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage
            exit 64
            ;;
    esac
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
config_file=${NIXGL_NVIDIA_CONFIG_FILE:-$repo_root/home/hosts/linux.nix}

first_line() {
    sed -n '1p'
}

configured_version() {
    [[ -r "$config_file" ]] || return 1
    sed -n 's/^[[:space:]]*_module\.args\.nixglNvidiaVersion[[:space:]]*=[[:space:]]*"\([^"]*\)";.*/\1/p' "$config_file" | first_line
}

running_version() {
    if [[ -v NIXGL_NVIDIA_RUNNING_VERSION ]]; then
        printf '%s\n' "$NIXGL_NVIDIA_RUNNING_VERSION"
        return 0
    fi

    if command -v nvidia-smi >/dev/null 2>&1; then
        nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null \
            | sed 's/[[:space:]]//g' \
            | first_line \
            || true
    fi

    if [[ -r /proc/driver/nvidia/version ]]; then
        sed -n 's/^NVRM version:.*  \([0-9][0-9.]*\)  .*/\1/p' /proc/driver/nvidia/version | first_line
    fi
}

version_in_file() {
    local file=$1
    [[ -f "$file" && -r "$file" ]] || return 1
    sed -n 's/.*nvidia-x11-\([0-9][0-9.]*\)-nixGL.*/\1/p' "$file" | first_line
}

store_refs_in_file() {
    local file=$1
    [[ -f "$file" && -r "$file" ]] || return 0
    grep -aoE '/nix/store/[A-Za-z0-9._+/-]+' "$file" 2>/dev/null || true
}

version_from_wrapper_file() {
    local queue=$1
    local depth file resolved version refs next

    for depth in 1 2 3 4; do
        next=
        for file in $queue; do
            [[ -n "$file" ]] || continue
            resolved=$(readlink -f "$file" 2>/dev/null || printf '%s\n' "$file")

            version=$(version_in_file "$resolved" || true)
            if [[ -n "$version" ]]; then
                printf '%s\n' "$version"
                return 0
            fi

            refs=$(store_refs_in_file "$resolved")
            if [[ -n "$refs" ]]; then
                next="$next $refs"
            fi
        done
        queue=$next
    done

    return 1
}

wrapper_version() {
    local commands cmd path version

    if [[ -v NIXGL_NVIDIA_WRAPPER_VERSION ]]; then
        printf '%s\n' "$NIXGL_NVIDIA_WRAPPER_VERSION"
        return 0
    fi

    commands=${NIXGL_NVIDIA_WRAPPER_COMMANDS:-kitty alacritty}
    for cmd in $commands; do
        path=$(command -v "$cmd" 2>/dev/null || true)
        [[ -n "$path" ]] || continue

        version=$(version_from_wrapper_file "$path" || true)
        if [[ -n "$version" ]]; then
            printf '%s (%s)\n' "$version" "$cmd"
            return 0
        fi
    done
}

configured=$(configured_version || true)
running=$(running_version | first_line || true)
wrapper=$(wrapper_version | first_line || true)
wrapper_plain=${wrapper%% *}

printf 'configured nixGL NVIDIA: %s\n' "${configured:-unknown}"
printf 'running NVIDIA driver:   %s\n' "${running:-unknown}"
printf 'active nixGL wrapper:    %s\n' "${wrapper:-unknown}"

if [[ -z "$configured" ]]; then
    printf '\nERROR: could not read nixglNvidiaVersion from %s\n' "$config_file" >&2
    exit 1
fi

if [[ -z "$running" ]]; then
    printf '\nUNKNOWN: no running NVIDIA driver detected. Nothing to compare.\n'
    exit 0
fi

if [[ "$running" != "$configured" ]]; then
    cat <<EOF

MISMATCH: running driver is $running, but nixGL is configured for $configured.

Fix:
  scripts/nvidia-driver-hash.sh $running
  update home/hosts/linux.nix with the printed version/hash
  bash setup.sh
EOF
    exit 1
fi

if [[ -n "$wrapper_plain" && "$wrapper_plain" != "$configured" ]]; then
    cat <<EOF

MISMATCH: home/hosts/linux.nix is configured for $configured, but the active wrapper uses $wrapper_plain.

Fix:
  bash setup.sh
EOF
    exit 1
fi

printf '\nOK: nixGL NVIDIA pin matches the running driver.\n'
