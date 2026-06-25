#!/usr/bin/env bash
# Reap stale orphaned OpenCode attach clients. Dry-run by default.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib/opencode-procs.sh
. "$script_dir/lib/opencode-procs.sh"

usage() {
    cat >&2 <<'EOF'
usage: opencode-reap.sh [--apply] [--older-than DURATION] [--signal SIGNAL] [--force]

Dry-runs by default. With --apply, sends SIGNAL (default TERM) to current-user
`opencode attach http...` client processes that are PPID 1, have no TTY (`?` or
`??`), are attached to the configured shared server URL, and are older than
DURATION (default 1d).

DURATION accepts seconds or a number followed by s, m, h, or d.
--force is shorthand for --signal KILL.

Environment overrides:
  OPENCODE_SHARED_HOST
  OPENCODE_SHARED_PORT
  OPENCODE_SHARED_URL
  OPENCODE_REAP_URL
  OPENCODE_REAP_PROCESS_FILE
  OPENCODE_REAP_USER
  OPENCODE_REAP_KILL_LOG  append "SIGNAL PID" instead of calling kill, for tests
EOF
}

apply=0
threshold=1d
signal=TERM

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --apply)
            apply=1
            shift
            ;;
        --older-than)
            [[ $# -ge 2 ]] || { usage; exit 64; }
            threshold=$2
            shift 2
            ;;
        --older-than=*)
            threshold=${1#--older-than=}
            shift
            ;;
        --signal)
            [[ $# -ge 2 ]] || { usage; exit 64; }
            signal=$2
            shift 2
            ;;
        --signal=*)
            signal=${1#--signal=}
            shift
            ;;
        --force)
            signal=KILL
            shift
            ;;
        *)
            usage
            exit 64
            ;;
    esac
done

duration_seconds() {
    local value=$1 number unit
    if [[ "$value" =~ ^([0-9]+)([smhd]?)$ ]]; then
        number=${BASH_REMATCH[1]}
        number=$((10#$number))
        unit=${BASH_REMATCH[2]:-s}
        case "$unit" in
            s) printf '%s\n' "$number" ;;
            m) printf '%s\n' $((number * 60)) ;;
            h) printf '%s\n' $((number * 3600)) ;;
            d) printf '%s\n' $((number * 86400)) ;;
        esac
        return 0
    fi

    return 1
}

elapsed_seconds() {
    local value=$1 days=0 days10 time_part parts

    time_part=$value
    if [[ "$time_part" == *-* ]]; then
        days=${time_part%%-*}
        time_part=${time_part#*-}
    fi
    days10=$((10#$days))

    IFS=: read -r -a parts <<< "$time_part"
    case "${#parts[@]}" in
        2) printf '%s\n' $((days10 * 86400 + 10#${parts[0]} * 60 + 10#${parts[1]})) ;;
        3) printf '%s\n' $((days10 * 86400 + 10#${parts[0]} * 3600 + 10#${parts[1]} * 60 + 10#${parts[2]})) ;;
        *) return 1 ;;
    esac
}

validate_signal() {
    local signal_num
    case "$signal" in
        TERM|KILL|INT|HUP|QUIT) return 0 ;;
        ''|*[!0-9]*) return 1 ;;
    esac

    signal_num=$((10#$signal))
    [[ "$signal_num" -ge 1 && "$signal_num" -le 64 ]]
}

send_signal() {
    local pid=$1
    if [[ -n "${OPENCODE_REAP_KILL_LOG:-}" ]]; then
        printf '%s %s\n' "$signal" "$pid" >> "$OPENCODE_REAP_KILL_LOG"
    else
        kill "-$signal" "$pid"
    fi
}

threshold_seconds=$(duration_seconds "$threshold") || {
    printf 'opencode-reap: invalid duration: %s\n' "$threshold" >&2
    exit 64
}

validate_signal || {
    printf 'opencode-reap: invalid signal: %s\n' "$signal" >&2
    exit 64
}

current_user=${OPENCODE_REAP_USER:-${USER:-$(id -un)}}
host=${OPENCODE_SHARED_HOST:-127.0.0.1}
port=${OPENCODE_SHARED_PORT:-4096}
target_url=${OPENCODE_REAP_URL:-${OPENCODE_SHARED_URL:-http://$host:$port}}
found=0

printf 'opencode-reap: %s mode, threshold %s (%s seconds), signal %s, url %s\n' \
    "$([[ "$apply" -eq 1 ]] && printf apply || printf dry-run)" \
    "$threshold" \
    "$threshold_seconds" \
    "$signal" \
    "$target_url"

while read -r user pid ppid tty elapsed rss command; do
    [[ -n "${command:-}" ]] || continue
    [[ "$user" == "$current_user" ]] || continue
    [[ "$ppid" == 1 ]] || continue
    [[ "$tty" == "?" || "$tty" == "??" ]] || continue
    opencode_matches_attach_command "$command" "$target_url" || continue

    seconds=$(elapsed_seconds "$elapsed") || continue
    [[ "$seconds" -gt "$threshold_seconds" ]] || continue

    found=1
    if [[ "$apply" -eq 1 ]]; then
        printf 'signaling pid %s (%s, %s KiB): %s\n' "$pid" "$elapsed" "$rss" "$command"
        send_signal "$pid"
    else
        printf 'would signal pid %s (%s, %s KiB): %s\n' "$pid" "$elapsed" "$rss" "$command"
    fi
done < <(opencode_process_rows "${OPENCODE_REAP_PROCESS_FILE:-}")

if [[ "$found" -eq 0 ]]; then
    printf 'opencode-reap: no stale orphaned attach clients found\n'
fi
