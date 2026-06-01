# Small shell scripts shared across shells.
#
# When a shell function doesn't need to manipulate the caller's shell
# state (cwd, env, history) it's just a wrapper script and can live as
# a standalone executable on PATH. Both shells then call the same
# binary — no per-shell duplication.
#
# Functions that DO need shell-state access (cd-task, y, history) stay
# as per-shell functions, generated via cross-shell-functions.nix.
{ pkgs, ... }:

{
  home.packages = [
    # ripgrep + delta with default `-C2` context.
    (pkgs.writeShellApplication {
      name = "rd";
      runtimeInputs = [
        pkgs.ripgrep
        pkgs.delta
      ];
      text = ''
        context="-C2"
        for arg in "$@"; do
          case "$arg" in
            -C*) context="" ;;
          esac
        done
        if [ -n "$context" ]; then
          rg --json "$context" "$@" | delta
        else
          rg --json "$@" | delta
        fi
      '';
    })

    # Copy <file> to <file>.bak. Trivial wrapper.
    (pkgs.writeShellApplication {
      name = "backup";
      text = ''
        if [ "$#" -ne 1 ]; then
          echo "usage: backup <file>" >&2
          exit 2
        fi
        cp -r -- "$1" "$1.bak"
      '';
    })

    (pkgs.writeShellApplication {
      name = "nixgl-nvidia-doctor";
      runtimeInputs = [
        pkgs.bash
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
      ];
      text = ''
        export NIXGL_NVIDIA_CONFIG_FILE=${../../home/hosts/linux.nix}
        exec bash ${../../scripts/nixgl-nvidia-doctor.sh} "$@"
      '';
    })

    # Force Chromium's macOS window surface to repaint after it gets stuck
    # showing stale pixels while tab/browser state continues to update.
    (pkgs.writeShellApplication {
      name = "chromium-redraw";
      text = ''
        if [ "$(uname -s)" != "Darwin" ]; then
          echo "chromium-redraw: only supported on macOS" >&2
          exit 1
        fi

        /usr/bin/osascript <<'APPLESCRIPT'
        tell application "Chromium" to activate
        delay 0.2
        tell application "System Events"
          tell application process "Chromium"
            set frontmost to true
            if (count of windows) > 0 then
              set oldSize to size of window 1
              set newWidth to (item 1 of oldSize) - 1
              if newWidth < 1 then set newWidth to item 1 of oldSize
              set size of window 1 to {newWidth, item 2 of oldSize}
              delay 0.2
              set size of window 1 to oldSize
            end if
          end tell
          keystroke "h" using command down
        end tell
        delay 0.5
        tell application "Chromium" to activate
        APPLESCRIPT
      '';
    })

    # Route normal OpenCode TUI launches through one shared local server
    # so permission requests are visible to external API clients.
    (pkgs.writeShellApplication {
      name = "opencode-shared";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.curl
      ];
      text = ''
        host="''${OPENCODE_SHARED_HOST:-127.0.0.1}"
        port="''${OPENCODE_SHARED_PORT:-4096}"
        url="''${OPENCODE_SHARED_URL:-http://$host:$port}"
        launchd_label="''${OPENCODE_SHARED_LAUNCHD_LABEL:-dev.opencode.server}"
        systemd_service="''${OPENCODE_SHARED_SYSTEMD_SERVICE:-opencode-server.service}"

        health() {
          curl --fail --silent --max-time 1 "$url/global/health" >/dev/null 2>&1
        }

        start_server() {
          if health; then
            return 0
          fi

          case "$(uname -s)" in
            Darwin)
              uid="$(id -u)"
              domain="gui/$uid"
              plist="$HOME/Library/LaunchAgents/$launchd_label.plist"
              if ! launchctl print "$domain/$launchd_label" >/dev/null 2>&1 && [ -e "$plist" ]; then
                launchctl bootstrap "$domain" "$plist" >/dev/null 2>&1 || true
              fi
              launchctl kickstart "$domain/$launchd_label" >/dev/null 2>&1 || true
              ;;
            Linux)
              if command -v systemctl >/dev/null 2>&1; then
                systemctl --user start "$systemd_service" >/dev/null 2>&1 || true
              fi
              ;;
          esac

          for _ in $(seq 1 50); do
            if health; then
              return 0
            fi
            sleep 0.1
          done

          echo "opencode: shared server did not start at $url; check the managed user service logs" >&2
          return 1
        }

        contains_flag() {
          flag="$1"
          shift

          for arg in "$@"; do
            case "$arg" in
              "$flag"|"$flag"=*) return 0 ;;
            esac
          done

          return 1
        }

        parse_tui_args() {
          project_dir="$PWD"
          attach_args=()
          found_project=0

          while [ "$#" -gt 0 ]; do
            case "$1" in
              --)
                shift
                if [ "$#" -gt 0 ]; then
                  if [ "$found_project" -ne 0 ]; then
                    return 1
                  fi
                  project_dir="$1"
                  found_project=1
                  shift
                fi
                [ "$#" -eq 0 ] || return 1
                return 0
                ;;
              -c|--continue|--fork|--pure|--print-logs)
                attach_args+=("$1")
                shift
                ;;
              -s|--session|-p|--password|-u|--username|--log-level)
                [ "$#" -ge 2 ] || return 1
                attach_args+=("$1" "$2")
                shift 2
                ;;
              --session=*|--password=*|--username=*|--log-level=*)
                attach_args+=("$1")
                shift
                ;;
              --dir)
                [ "$#" -ge 2 ] || return 1
                if [ "$found_project" -ne 0 ]; then
                  return 1
                fi
                project_dir="$2"
                found_project=1
                shift 2
                ;;
              --dir=*)
                if [ "$found_project" -ne 0 ]; then
                  return 1
                fi
                project_dir="''${1#--dir=}"
                found_project=1
                shift
                ;;
              -*)
                return 1
                ;;
              *)
                if [ "$found_project" -ne 0 ]; then
                  return 1
                fi
                project_dir="$1"
                found_project=1
                shift
                ;;
            esac
          done
        }

        if [ "$#" -gt 0 ]; then
          case "$1" in
            -h|--help|-v|--version|completion|acp|mcp|attach|debug|providers|auth|agent|upgrade|uninstall|serve|web|models|stats|export|import|github|pr|session|plugin|plug|db|start|stop|restart|status)
              exec opencode "$@"
              ;;
            run)
              shift
              case "''${1:-}" in
                -h|--help|-v|--version)
                  exec opencode run "$@"
                  ;;
              esac

              if contains_flag --attach "$@"; then
                exec opencode run "$@"
              fi

              start_server
              if contains_flag --dir "$@"; then
                exec opencode run --attach "$url" "$@"
              fi
              exec opencode run --attach "$url" --dir "$PWD" "$@"
              ;;
          esac
        fi

        if ! parse_tui_args "$@"; then
          exec opencode "$@"
        fi

        start_server
        exec opencode attach "$url" --dir "$project_dir" "''${attach_args[@]}"
      '';
    })
  ];
}
