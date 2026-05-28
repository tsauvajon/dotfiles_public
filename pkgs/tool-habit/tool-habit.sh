#!/bin/sh

tool_color="$(printf '\033[1;36m')"
command_color="$(printf '\033[1;33m')"
reset="$(printf '\033[0m')"

color_commands() {
  text=$1

  while :; do
    case $text in
      *\`*)
        before=${text%%\`*}
        rest=${text#*\`}
        case $rest in
          *\`*)
            command=${rest%%\`*}
            text=${rest#*\`}
            printf '%s%s%s%s' "$before" "$command_color" "$command" "$reset"
            ;;
          *)
            printf '%s`%s' "$before" "$rest"
            return
            ;;
        esac
        ;;
      *)
        printf '%s' "$text"
        return
        ;;
    esac
  done
}

color_habit() {
  line=$1

  if [ -n "${NO_COLOR:-}" ]; then
    printf '%s\n' "$line"
    return
  fi

  case $line in
    *': '*)
      tool=${line%%: *}
      rest=${line#*: }
      printf '%s%s%s: ' "$tool_color" "$tool" "$reset"
      color_commands "$rest"
      printf '\n'
      ;;
    *)
      color_commands "$line"
      printf '\n'
      ;;
  esac
}

habit="$(@fortune@ "$@" "@habits@")" || exit $?
color_habit "$habit"
