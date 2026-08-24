#!/usr/bin/env bash
# Watch the shared OpenCode server for permission prompts and answer low-risk ones.
set -u

TODAY="${OPENCODE_PERMISSION_MONITOR_DATE:-$(date -u +%F)}"
BASE_URL="${OPENCODE_PERMISSION_MONITOR_URL:-http://127.0.0.1:4096}"
LOG_FILE="${OPENCODE_PERMISSION_MONITOR_LOG:-$HOME/Documents/Obsidian/Tooling/OpenCode Permission Decisions $TODAY.md}"
INTERVAL="${OPENCODE_PERMISSION_MONITOR_INTERVAL:-4}"
STATE_FILE="${OPENCODE_PERMISSION_MONITOR_STATE:-${TMPDIR:-/tmp}/opencode-permission-monitor.seen}"
LIST_TIMEOUT="${OPENCODE_PERMISSION_MONITOR_LIST_TIMEOUT:-${OPENCODE_PERMISSION_MONITOR_TIMEOUT:-1}}"
REPLY_TIMEOUT="${OPENCODE_PERMISSION_MONITOR_REPLY_TIMEOUT:-${OPENCODE_PERMISSION_MONITOR_TIMEOUT:-5}}"
INCLUDE_SESSION_HISTORY="${OPENCODE_PERMISSION_MONITOR_INCLUDE_SESSION_HISTORY:-0}"
PROCESS_FILE="${OPENCODE_PERMISSION_MONITOR_PROCESS_FILE:-}"
CANDIDATE_START='<!-- opencode-permission-monitor:candidates:start -->'
CANDIDATE_END='<!-- opencode-permission-monitor:candidates:end -->'
ONCE=0
DRY_RUN=0
QUIET=0

usage() {
    printf 'Usage: %s [--once] [--dry-run] [--include-session-history] [--interval seconds] [--url url] [--log file] [--state file] [--quiet]\n' "$0"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --once)
            ONCE=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --quiet)
            QUIET=1
            shift
            ;;
        --include-session-history)
            INCLUDE_SESSION_HISTORY=1
            shift
            ;;
        --interval)
            [[ $# -ge 2 ]] || { usage >&2; exit 64; }
            INTERVAL="$2"
            shift 2
            ;;
        --url)
            [[ $# -ge 2 ]] || { usage >&2; exit 64; }
            BASE_URL="$2"
            shift 2
            ;;
        --log)
            [[ $# -ge 2 ]] || { usage >&2; exit 64; }
            LOG_FILE="$2"
            shift 2
            ;;
        --state)
            [[ $# -ge 2 ]] || { usage >&2; exit 64; }
            STATE_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

mkdir -p "$(dirname "$STATE_FILE")" "$(dirname "$LOG_FILE")"
touch "$STATE_FILE"

timestamp() {
    date -u '+%Y-%m-%d %H:%M:%S UTC'
}

say() {
    [[ "$QUIET" -eq 1 ]] && return
    printf '[%s] %s\n' "$(timestamp)" "$*"
}

redact() {
    jq -c 'walk(if type == "string" then
      gsub("(?i)(?<key>token|secret|password|passwd|api[_-]?key|authorization|bearer)=([^\\s\"'"'"']+)"; "\(.key)=[REDACTED]") |
      gsub("(?i)(?<prefix>Bearer )[A-Za-z0-9._~+/=-]+"; "\(.prefix)[REDACTED]") |
      gsub("op://[^\\s\"'"'"']+"; "op://[REDACTED]")
    else . end)'
}

ensure_log() {
    [[ -s "$LOG_FILE" ]] && return
    {
        printf -- '---\n'
        printf 'title: OpenCode permission decisions\n'
        printf 'created: %s\n' "$TODAY"
        printf 'tags: [opencode, tooling, log, permissions]\n'
        printf -- '---\n\n'
        printf '# OpenCode Permission Decisions %s\n\n' "$TODAY"
        printf 'Automated monitor log for OpenCode permission prompts.\n\n'
        printf 'Policy: allow liberally for routine development and local disk access; reject requests that look like destructive disk operations, secret exfiltration, or credential disclosure. Token-like values are redacted before logging.\n\n'
        printf '## Decisions\n'
    } > "$LOG_FILE"
}

destructive_regex='(^|[;&|[:space:]])(sudo[[:space:]].*(rm[[:space:]].*(-rf|-fr|--recursive|--force)|dd[[:space:]].*of=/dev|diskutil[[:space:]].*(erase|partition)|mkfs)|dd[[:space:]].*of=/dev|diskutil[[:space:]].*(erase|partition)|mkfs(\.|[[:space:]]|$)|shred[[:space:]]|srm[[:space:]]|find[[:space:]].*[[:space:]]-delete([;&|[:space:]]|$)|git[[:space:]]+clean[[:space:]].*-[^[:space:]]*[fdx]|truncate[[:space:]].*-s[[:space:]]*0)'
secret_regex='(^|[;&|[:space:]])(printenv|set)([[:space:]]|$)|(^|[;&|[:space:]])env([[:space:]]*$|[[:space:]]*[|>])|security[[:space:]].*(-w|find-generic-password|find-internet-password)|op[[:space:]]+(read|item[[:space:]]+get)|pass[[:space:]]+show|gpg[[:space:]].*--decrypt|cat[[:space:]].*(\.env|id_rsa|id_ed25519|\.pem|\.key)|rg[[:space:]].*(token|secret|password|api[_-]?key).*(\.env|id_rsa|id_ed25519|\.pem|\.key)|grep[[:space:]].*(token|secret|password|api[_-]?key).*(\.env|id_rsa|id_ed25519|\.pem|\.key)'
secret_path_regex='(^|/)(\.env[^/]*|id_rsa|id_ed25519|\.gnupg|\.ssh|\.aws|\.kube|\.password-store|Library/Keychains)(/|$)|\.(pem|key)$'

is_destructive_command() {
    local text="$1"
    [[ "$text" =~ $destructive_regex ]] && return 0

    if [[ "$text" =~ (^|[\;\&\|[:space:]])([^\;\&\|[:space:]]*/)?rm[[:space:]] ]]; then
        if [[ "$text" =~ (^|[\;\&\|[:space:]])([^\;\&\|[:space:]]*/)?rm[^\;\&\|]*-[^\;\&\|[:space:]]*r ]] && [[ "$text" =~ (^|[\;\&\|[:space:]])([^\;\&\|[:space:]]*/)?rm[^\;\&\|]*-[^\;\&\|[:space:]]*f ]]; then
            return 0
        fi
        if [[ "$text" =~ (^|[\;\&\|[:space:]])([^\;\&\|[:space:]]*/)?rm[[:space:]].*-([^[:space:]\;\&\|]*r[^[:space:]\;\&\|]*f|[^[:space:]\;\&\|]*f[^[:space:]\;\&\|]*r) ]]; then
            return 0
        fi
        if [[ "$text" =~ (^|[\;\&\|[:space:]])([^\;\&\|[:space:]]*/)?rm[[:space:]].*--recursive ]] && [[ "$text" =~ (^|[\;\&\|[:space:]])([^\;\&\|[:space:]]*/)?rm[[:space:]].*--force ]]; then
            return 0
        fi
    fi

    return 1
}

decide_legacy() {
    local req="$1"
    local permission text
    permission="$(jq -r '.permission // ""' <<< "$req")"
    text="$(jq -r '[.permission, (.patterns // [] | join(" ")), (.always // [] | join(" ")), (.metadata // {} | tostring)] | join(" ")' <<< "$req")"

    if [[ "$permission" == "external_directory" ]]; then
        if [[ "$text" =~ $secret_path_regex ]]; then
            printf '%s\t%s\n' reject 'secret-bearing path'
        else
            printf '%s\t%s\n' always 'routine external directory access'
        fi
        return
    fi

    if [[ "$permission" == "read" || "$permission" == "edit" ]]; then
        if [[ "$text" =~ $secret_path_regex ]]; then
            printf '%s\t%s\n' reject 'secret-bearing file path'
        else
            printf '%s\t%s\n' always 'routine file access'
        fi
        return
    fi

    if [[ "$permission" == "bash" ]]; then
        if is_destructive_command "$text"; then
            printf '%s\t%s\n' reject 'destructive disk operation'
        elif [[ "$text" =~ $secret_regex ]]; then
            printf '%s\t%s\n' reject 'possible secret disclosure'
        else
            printf '%s\t%s\n' always 'routine shell command'
        fi
        return
    fi

    printf '%s\t%s\n' always 'non-risky OpenCode permission'
}

decide_v2() {
    local req="$1"
    local action text
    action="$(jq -r '.action // ""' <<< "$req")"
    text="$(jq -r '[.action, (.resources // [] | join(" ")), (.save // [] | join(" ")), (.metadata // {} | tostring), (.source // {} | tostring)] | join(" ")' <<< "$req")"

    if [[ "$text" =~ $secret_path_regex ]]; then
        printf '%s\t%s\n' reject 'secret-bearing path'
    elif is_destructive_command "$text"; then
        printf '%s\t%s\n' reject 'destructive disk operation'
    elif [[ "$text" =~ $secret_regex ]]; then
        printf '%s\t%s\n' reject 'possible secret disclosure'
    elif [[ "$action" =~ ^(bash|read|edit|external_directory|glob|grep|list)$ ]]; then
        printf '%s\t%s\n' always 'routine development access'
    else
        printf '%s\t%s\n' always 'non-risky OpenCode permission'
    fi
}

already_seen() {
    local key="$1"
    grep -Fxq "$key" "$STATE_FILE"
}

mark_seen() {
    local key="$1"
    printf '%s\n' "$key" >> "$STATE_FILE"
}

append_log() {
    local kind="$1" location="$2" req="$3" reply="$4" reason="$5" api_status="$6"
    local command safe_req
    ensure_log
    command="$(request_command "$req")"
    safe_req="$(redact <<< "$req")"
    {
        printf '\n### %s\n\n' "$(timestamp)"
        printf -- '- Location: `%s`\n' "$location"
        printf -- '- Decision: `%s`\n' "$reply"
        printf -- '- Reason: %s\n' "$reason"
        printf -- '- API status: `%s`\n' "$api_status"
        if [[ -n "$command" ]]; then
            printf -- '- Command:\n\n'
            printf '```sh\n%s\n```\n' "$command"
        fi
        printf -- '- Request:\n\n'
        printf '```json\n%s\n```\n' "$safe_req"
    } >> "$LOG_FILE"
    update_candidate_rules
}

normalize_candidate_pattern() {
    local pattern="$1"
    case "$pattern" in
        /Users/thomas/*)
            pattern="~/${pattern#/Users/thomas/}"
            ;;
    esac

    if [[ "$pattern" =~ ^/var/folders/[^/]+/[^/]+/T(/.*)?$ ]]; then
        pattern='/var/folders/*/*/T/*'
    elif [[ "$pattern" =~ ^/nix/store/[^/]+-home-manager-generation/activate([[:space:]].*)?$ ]]; then
        pattern='/nix/store/*-home-manager-generation/activate *'
    fi

    printf '%s\n' "$pattern"
}

candidate_bucket() {
    local pattern
    pattern="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$pattern" in
        *corp.example*|*deploy-cli*|*glim*|*internal-admin*|*private-registry*|*vault\ status*|~/.agents/*|~/.claude/*|~/.corp/*|~/work/*)
            printf 'Private Overlay\n'
            ;;
        *)
            printf 'Public Base\n'
            ;;
    esac
}

candidate_entries() {
    local decision req permission pattern normalized bucket rule_decision
    awk '
        /^- Decision: `/ {
            decision = $0
            sub(/^- Decision: `/, "", decision)
            sub(/`.*$/, "", decision)
        }
        /^```json$/ { in_json = 1; json = ""; next }
        /^```$/ && in_json { print decision "\t" json; in_json = 0; next }
        in_json { json = json $0 }
    ' "$LOG_FILE" | while IFS=$'\t' read -r decision req; do
        [[ -n "$req" ]] || continue
        permission="$(jq -r '.permission // .action // "unknown"' <<< "$req" 2>/dev/null)" || continue
        if [[ "$decision" == "reject" ]]; then
            rule_decision='reject'
        else
            rule_decision='allow'
        fi

        jq -r 'if has("always") then .always[]? elif has("save") then .save[]? else .resources[]? end' <<< "$req" 2>/dev/null |
            while IFS= read -r pattern; do
                [[ -n "$pattern" ]] || continue
                normalized="$(normalize_candidate_pattern "$pattern")"
                if [[ "$rule_decision" == "reject" ]]; then
                    bucket='Rejected'
                else
                    bucket="$(candidate_bucket "$normalized")"
                fi
                printf '%s\t%s\t%s\t%s\n' "$bucket" "$permission" "$normalized" "$rule_decision"
            done
    done
}

write_candidate_group() {
    local entries_file="$1" bucket="$2" permission="$3"
    awk -F '\t' -v bucket="$bucket" -v permission="$permission" '$1 == bucket && $2 == permission { print $3 "\t" $4 }' "$entries_file" |
        sort | uniq -c | sort -k2,2 |
        awk -F '\t' -v permission="$permission" '
            BEGIN { first = 1 }
            {
                left = $1
                decision = $2
                sub(/^ */, "", left)
                count = left
                sub(/ .*/, "", count)
                pattern = left
                sub(/^[0-9]+ /, "", pattern)
                if (first) {
                    printf "\n#### %s\n\n", permission
                    print "| Count | Pattern | Decision |"
                    print "| ---: | --- | --- |"
                    first = 0
                }
                printf "| %s | `%s` | `%s` |\n", count, pattern, decision
            }
        '
}

generate_candidate_summary() {
    local entries_file="$1" bucket permission
    printf '%s\n' "$CANDIDATE_START"
    printf '## Candidate Permission Rules\n\n'
    printf 'Generated from allowed/rejected permission prompts in this note. Review before copying into dotfiles.\n'
    for bucket in 'Public Base' 'Private Overlay' 'Rejected'; do
        if awk -F '\t' -v bucket="$bucket" '$1 == bucket { found = 1 } END { exit found ? 0 : 1 }' "$entries_file"; then
            printf '\n### %s\n' "$bucket"
            awk -F '\t' -v bucket="$bucket" '$1 == bucket { print $2 }' "$entries_file" | sort -u |
                while IFS= read -r permission; do
                    write_candidate_group "$entries_file" "$bucket" "$permission"
                done
        fi
    done
    printf '\n%s\n' "$CANDIDATE_END"
}

update_candidate_rules() {
    local entries_file body_file summary_file new_file
    [[ -s "$LOG_FILE" ]] || return
    entries_file="$(mktemp)"
    body_file="$(mktemp)"
    summary_file="$(mktemp)"
    new_file="$(mktemp)"
    candidate_entries > "$entries_file"
    if [[ ! -s "$entries_file" ]]; then
        rm -f "$entries_file" "$body_file" "$summary_file" "$new_file"
        return
    fi
    generate_candidate_summary "$entries_file" > "$summary_file"
    awk -v start="$CANDIDATE_START" -v end="$CANDIDATE_END" '
        $0 == start { skip = 1; next }
        $0 == end { skip = 0; next }
        !skip { print }
    ' "$LOG_FILE" > "$body_file"
    awk -v summary="$summary_file" '
        $0 == "## Decisions" {
            while ((getline line < summary) > 0) print line
            close(summary)
            print ""
        }
        { print }
    ' "$body_file" > "$new_file"
    mv "$new_file" "$LOG_FILE"
    rm -f "$entries_file" "$body_file" "$summary_file"
}

request_command() {
    redact <<< "$1" |
        jq -r '[
          .metadata.command?,
          .metadata.description?,
          .source.command?,
          .source.path?,
          ((.patterns // []) | join(" | ")),
          ((.resources // []) | join(" | "))
        ] | map(select(type == "string" and length > 0)) | first // ""'
}

request_summary() {
    redact <<< "$1" |
        jq -r 'if has("patterns") then (.permission + " " + ((.patterns // []) | join(" | "))) else (.action + " " + ((.resources // []) | join(" | "))) end' |
        jq -Rs 'gsub("\\s+"; " ") | .[0:220]' |
        tr -d '"'
}

reply_legacy() {
    local request_id="$1" directory="$2" reply="$3" reason="$4"
    local url encoded
    if [[ -n "$directory" ]]; then
        encoded="$(jq -nr --arg v "$directory" '$v|@uri')"
        url="$BASE_URL/permission/$request_id/reply?directory=$encoded"
    else
        url="$BASE_URL/permission/$request_id/reply"
    fi
    curl -sS --max-time "$REPLY_TIMEOUT" -o /dev/null -w '%{http_code}' -X POST "$url" \
        -H 'content-type: application/json' \
        --data "$(jq -nc --arg reply "$reply" --arg message "$reason" '{reply:$reply,message:$message}')"
}

reply_v2() {
    local session_id="$1" request_id="$2" reply="$3" reason="$4"
    curl -sS --max-time "$REPLY_TIMEOUT" -o /dev/null -w '%{http_code}' -X POST "$BASE_URL/api/session/$session_id/permission/$request_id/reply" \
        -H 'content-type: application/json' \
        --data "$(jq -nc --arg reply "$reply" --arg message "$reason" '{reply:$reply,message:$message}')"
}

legacy_requests() {
    local directory="$1" encoded url
    if [[ -n "$directory" ]]; then
        encoded="$(jq -nr --arg v "$directory" '$v|@uri')"
        url="$BASE_URL/permission?directory=$encoded"
    else
        url="$BASE_URL/permission"
    fi
    curl -fsS --max-time "$LIST_TIMEOUT" "$url" 2>/dev/null || printf '[]'
}

v2_requests() {
    local directory="$1" encoded url
    if [[ -n "$directory" ]]; then
        encoded="$(jq -nr --arg v "$directory" '$v|@uri')"
        url="$BASE_URL/api/permission/request?location%5Bdirectory%5D=$encoded"
    else
        url="$BASE_URL/api/permission/request"
    fi
    curl -fsS --max-time "$LIST_TIMEOUT" "$url" 2>/dev/null || printf '{"data":[]}'
}

process_legacy_location() {
    local directory="$1" requests req id sid decision reply reason http_status key summary
    requests="$(legacy_requests "$directory")"
    jq -c '.[]?' <<< "$requests" | while IFS= read -r req; do
        id="$(jq -r '.id' <<< "$req")"
        sid="$(jq -r '.sessionID' <<< "$req")"
        key="legacy:$sid:$id"
        already_seen "$key" && continue
        decision="$(decide_legacy "$req")"
        reply="${decision%%$'\t'*}"
        reason="${decision#*$'\t'}"
        summary="$(request_summary "$req")"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            say "v1 ${directory:-<default>} $id -> $reply ($reason) dry-run :: $summary"
            continue
        fi
        http_status="$(reply_legacy "$id" "$directory" "$reply" "$reason")"
        say "v1 ${directory:-<default>} $id -> $reply ($reason) status=$http_status :: $summary"
        append_log v1 "${directory:-<default>}" "$req" "$reply" "$reason" "$http_status"
        [[ "$http_status" == "200" || "$http_status" == "204" ]] && mark_seen "$key"
    done
}

process_v2_location() {
    local directory="$1" requests req id sid decision reply reason http_status key summary
    requests="$(v2_requests "$directory")"
    jq -c '.data[]?' <<< "$requests" | while IFS= read -r req; do
        id="$(jq -r '.id' <<< "$req")"
        sid="$(jq -r '.sessionID' <<< "$req")"
        key="v2:$sid:$id"
        already_seen "$key" && continue
        decision="$(decide_v2 "$req")"
        reply="${decision%%$'\t'*}"
        reason="${decision#*$'\t'}"
        summary="$(request_summary "$req")"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            say "v2 ${directory:-<default>} $id -> $reply ($reason) dry-run :: $summary"
            continue
        fi
        http_status="$(reply_v2 "$sid" "$id" "$reply" "$reason")"
        say "v2 ${directory:-<default>} $id -> $reply ($reason) status=$http_status :: $summary"
        append_log v2 "${directory:-<default>}" "$req" "$reply" "$reason" "$http_status"
        [[ "$http_status" == "200" || "$http_status" == "204" ]] && mark_seen "$key"
    done
}

directories_from_api() {
    curl -fsS --max-time "$LIST_TIMEOUT" "$BASE_URL/api/session?limit=500&order=desc" 2>/dev/null |
        jq -r '.data[]?.location.directory // empty'
}

directories_from_processes() {
    process_commands() {
        if [[ -n "$PROCESS_FILE" ]]; then
            while IFS= read -r cmd; do
                printf '%s\n' "$cmd"
            done < "$PROCESS_FILE"
        else
            ps -axo command
        fi
    }

    process_commands | while IFS= read -r cmd; do
        case "$cmd" in
            *"opencode attach "*" --dir "*)
                local rest dir
                rest="${cmd#* --dir }"
                case "$rest" in
                    "'*")
                        dir="${rest#\'}"
                        dir="${dir%%\'*}"
                        ;;
                    \"*)
                        dir="${rest#\"}"
                        dir="${dir%%\"*}"
                        ;;
                    *)
                        dir="${rest%% --*}"
                        dir="${dir%% -*}"
                        ;;
                esac
                printf '%s\n' "$dir"
                ;;
            *"opencode attach "*" --dir="*)
                local rest dir
                rest="${cmd#* --dir=}"
                case "$rest" in
                    "'*")
                        dir="${rest#\'}"
                        dir="${dir%%\'*}"
                        ;;
                    \"*)
                        dir="${rest#\"}"
                        dir="${dir%%\"*}"
                        ;;
                    *)
                        dir="${rest%% --*}"
                        dir="${dir%% -*}"
                        ;;
                esac
                printf '%s\n' "$dir"
                ;;
        esac
    done
}

known_directories() {
    {
        printf '\n'
        directories_from_processes
        if [[ "$INCLUDE_SESSION_HISTORY" -eq 1 ]]; then
            directories_from_api
        fi
    } | awk 'NF' | sort -u
}

poll_once() {
    local count=0 found_before found_after
    found_before="$(wc -l < "$STATE_FILE" | tr -d ' ')"
    process_legacy_location ""
    process_v2_location ""
    while IFS= read -r dir; do
        [[ -n "$dir" ]] || continue
        count=$((count + 1))
        process_legacy_location "$dir"
        process_v2_location "$dir"
    done < <(known_directories)
    found_after="$(wc -l < "$STATE_FILE" | tr -d ' ')"
    if [[ "$found_before" == "$found_after" ]]; then
        say "poll complete; checked $count directories; no new answered permissions"
    else
        say "poll complete; checked $count directories"
    fi
}

if [[ "${OPENCODE_PERMISSION_MONITOR_SOURCE_ONLY:-0}" = 1 ]]; then
    return 0 2>/dev/null || exit 0
fi

ensure_log
if [[ "$DRY_RUN" -eq 1 ]]; then
    say "starting dry-run; no API replies or Obsidian decision entries will be written"
else
    printf '\n### %s - monitor started\n\n- Base URL: `%s`\n- Poll interval: `%ss`\n- List timeout: `%ss`\n- Reply timeout: `%ss`\n- Include session history: `%s`\n- State file: `%s`\n' "$(timestamp)" "$BASE_URL" "$INTERVAL" "$LIST_TIMEOUT" "$REPLY_TIMEOUT" "$INCLUDE_SESSION_HISTORY" "$STATE_FILE" >> "$LOG_FILE"
    say "monitor started; base=$BASE_URL interval=${INTERVAL}s log=$LOG_FILE"
fi

while true; do
    poll_once
    [[ "$ONCE" -eq 1 ]] && break
    sleep "$INTERVAL"
done
