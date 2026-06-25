#!/usr/bin/env bash
# Read-only diagnostics for the Home Manager-managed OpenCode shared server.
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
# shellcheck source=scripts/lib/opencode-procs.sh
. "$script_dir/lib/opencode-procs.sh"

usage() {
    cat >&2 <<'EOF'
usage: opencode-server-status.sh

Reports shared OpenCode server health, user-service state, process stats,
attached client count, log sizes, latest listener warning, and pending restart
marker state. This command is read-only and never mutates the service.

Environment overrides:
  OPENCODE_SHARED_HOST
  OPENCODE_SHARED_PORT
  OPENCODE_SHARED_URL
  OPENCODE_SHARED_LAUNCHD_LABEL
  OPENCODE_SHARED_SYSTEMD_SERVICE
  OPENCODE_SHARED_LOG_FILE
  OPENCODE_SHARED_ERROR_LOG_FILE
  OPENCODE_SHARED_PENDING_RESTART_FILE
  OPENCODE_STATUS_UNAME
  OPENCODE_STATUS_HEALTH
  OPENCODE_STATUS_SYSTEMD_SHOW
  OPENCODE_STATUS_LAUNCHCTL_PRINT
  OPENCODE_STATUS_PROCESS_FILE
  OPENCODE_STATUS_USER
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

xdg_data_home=${XDG_DATA_HOME:-$HOME/.local/share}
xdg_cache_home=${XDG_CACHE_HOME:-$HOME/.cache}

host=${OPENCODE_SHARED_HOST:-127.0.0.1}
port=${OPENCODE_SHARED_PORT:-4096}
url=${OPENCODE_SHARED_URL:-http://$host:$port}
launchd_label=${OPENCODE_SHARED_LAUNCHD_LABEL:-dev.opencode.server}
systemd_service=${OPENCODE_SHARED_SYSTEMD_SERVICE:-opencode-server.service}
log_file=${OPENCODE_SHARED_LOG_FILE:-$xdg_data_home/opencode/shared-server.log}
error_log_file=${OPENCODE_SHARED_ERROR_LOG_FILE:-$xdg_data_home/opencode/shared-server-error.log}
pending_restart_file=${OPENCODE_SHARED_PENDING_RESTART_FILE:-$xdg_cache_home/dotfiles/opencode-server.pending-restart}
os_name=${OPENCODE_STATUS_UNAME:-$(uname -s)}
current_user=${OPENCODE_STATUS_USER:-${USER:-$(id -un)}}

health_status() {
    if [[ "${OPENCODE_STATUS_HEALTH+x}" = x ]]; then
        case "$OPENCODE_STATUS_HEALTH" in
            ok|healthy|up) printf 'healthy\n' ;;
            *) printf 'unhealthy\n' ;;
        esac
        return 0
    fi

    if curl --fail --silent --max-time 1 "$url/global/health" >/dev/null 2>&1; then
        printf 'healthy\n'
    else
        printf 'unhealthy\n'
    fi
}

attached_client_count() {
    local count=0 user pid _ppid _tty elapsed rss command

    while read -r user pid _ppid _tty elapsed rss command; do
        [[ -n "${command:-}" ]] || continue
        [[ "$user" == "$current_user" ]] || continue
        if opencode_matches_attach_command "$command" "$url"; then
            count=$((count + 1))
        fi
    done < <(opencode_process_rows "${OPENCODE_STATUS_PROCESS_FILE:-}")

    printf '%s\n' "$count"
}

process_stats_for_pid() {
    local wanted_pid=$1
    local user pid _ppid _tty elapsed rss command

    [[ -n "$wanted_pid" && "$wanted_pid" != 0 ]] || return 1

    while read -r user pid _ppid _tty elapsed rss command; do
        [[ "$pid" == "$wanted_pid" ]] || continue
        printf 'RSS %s KiB, elapsed %s\n' "$rss" "$elapsed"
        return 0
    done < <(opencode_process_rows "${OPENCODE_STATUS_PROCESS_FILE:-}")

    ps -p "$wanted_pid" -o rss= -o etime= 2>/dev/null \
        | sed -n 's/^[[:space:]]*\([^[:space:]]\{1,\}\)[[:space:]]\{1,\}\([^[:space:]]\{1,\}\).*$/RSS \1 KiB, elapsed \2/p' \
        | sed -n '1p'
}

service_state() {
    local output state substate pid active_count uid domain

    case "$os_name" in
        Darwin)
            uid=$(id -u)
            domain="gui/$uid"
            if [[ "${OPENCODE_STATUS_LAUNCHCTL_PRINT+x}" = x ]]; then
                output=$OPENCODE_STATUS_LAUNCHCTL_PRINT
            else
                output=$(launchctl print "$domain/$launchd_label" 2>/dev/null || true)
            fi
            state=$(printf '%s\n' "$output" | sed -n 's/^[[:space:]]*state = \(.*\)$/\1/p' | sed -n '1p')
            pid=$(printf '%s\n' "$output" | sed -n 's/^[[:space:]]*pid = \([0-9][0-9]*\).*$/\1/p' | sed -n '1p')
            active_count=$(printf '%s\n' "$output" | sed -n 's/^[[:space:]]*active count = \([0-9][0-9]*\).*$/\1/p' | sed -n '1p')
            printf '%s|%s|%s\n' "${state:-unavailable}" "${pid:-}" "active-count=${active_count:-unknown}"
            ;;
        Linux)
            if [[ "${OPENCODE_STATUS_SYSTEMD_SHOW+x}" = x ]]; then
                output=$OPENCODE_STATUS_SYSTEMD_SHOW
            elif command -v systemctl >/dev/null 2>&1; then
                output=$(systemctl --user show "$systemd_service" \
                    --property=ActiveState \
                    --property=SubState \
                    --property=MainPID \
                    --no-pager 2>/dev/null || true)
            else
                output=
            fi
            state=$(printf '%s\n' "$output" | sed -n 's/^ActiveState=//p' | sed -n '1p')
            substate=$(printf '%s\n' "$output" | sed -n 's/^SubState=//p' | sed -n '1p')
            pid=$(printf '%s\n' "$output" | sed -n 's/^MainPID=//p' | sed -n '1p')
            [[ "$pid" == 0 ]] && pid=
            if [[ -n "$state" && -n "$substate" ]]; then
                state="$state/$substate"
            fi
            printf '%s|%s|%s\n' "${state:-unavailable}" "${pid:-}" "service=$systemd_service"
            ;;
        *)
            printf 'unavailable||unsupported-os=%s\n' "$os_name"
            ;;
    esac
}

log_size() {
    local file=$1
    if [[ -e "$file" ]]; then
        printf '%s bytes' "$(wc -c < "$file" | tr -d '[:space:]')"
    else
        printf 'missing'
    fi
}

latest_listener_warning() {
    for file in "$log_file" "$error_log_file"; do
        [[ -r "$file" ]] || continue
        grep -iE 'listener.*warn|warn.*listener' "$file" 2>/dev/null || true
    done | tail -n 1
}

pending_restart_state() {
    local bytes reason created_at
    if [[ -e "$pending_restart_file" ]]; then
        bytes=$(wc -c < "$pending_restart_file" | tr -d '[:space:]')
        reason=$(sed -n 's/^reason=//p' "$pending_restart_file" 2>/dev/null | sed -n '1p')
        created_at=$(sed -n 's/^created_at=//p' "$pending_restart_file" 2>/dev/null | sed -n '1p')
        printf 'present (%s bytes, reason: %s, created_at: %s)' \
            "$bytes" \
            "${reason:-unknown}" \
            "${created_at:-unknown}"
    else
        printf 'absent'
    fi
}

service=$(service_state)
IFS='|' read -r state pid detail <<< "$service"

printf 'OpenCode shared server\n'
printf '  url: %s\n' "$url"
printf '  health: %s\n' "$(health_status)"
printf '  service: %s (%s)\n' "$state" "$detail"
if [[ -n "$pid" ]]; then
    printf '  pid: %s\n' "$pid"
    stats=$(process_stats_for_pid "$pid" || true)
    printf '  process: %s\n' "${stats:-unavailable}"
else
    printf '  pid: unavailable\n'
    printf '  process: unavailable\n'
fi
printf '  attached TUI clients: %s\n' "$(attached_client_count)"
printf '  stdout log: %s (%s)\n' "$log_file" "$(log_size "$log_file")"
printf '  stderr log: %s (%s)\n' "$error_log_file" "$(log_size "$error_log_file")"
warning=$(latest_listener_warning || true)
printf '  latest listener warning: %s\n' "${warning:-none}"
printf '  pending restart file: %s (%s)\n' "$pending_restart_file" "$(pending_restart_state)"
