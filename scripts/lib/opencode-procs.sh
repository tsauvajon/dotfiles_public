#!/usr/bin/env bash
# Shared process helpers for OpenCode ops scripts.

opencode_process_rows() {
    local process_file=${1:-}

    if [[ -n "$process_file" ]]; then
        cat "$process_file"
        return 0
    fi

    ps -axo user=,pid=,ppid=,tty=,etime=,rss=,command= 2>/dev/null || true
}

opencode_matches_attach_command() {
    local command=$1
    local target_url=$2

    case " $command " in
        *"/opencode attach $target_url "*|*" opencode attach $target_url "*) return 0 ;;
    esac
    return 1
}
