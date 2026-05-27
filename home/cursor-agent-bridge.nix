{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.opencode.cursorAgentBridge;
  port = "43115";
  host = "127.0.0.1";
  url = "http://${host}:${port}";
  label = "dev.opencode.cursor-agent-bridge";
  systemdService = "opencode-cursor-agent-bridge.service";
  configDir = "${config.xdg.configHome}/opencode";
  bridgeScript = "${configDir}/plugins/cursor-agent-bridge.ts";

  defaultPath = lib.concatStringsSep ":" (
    [
      "${config.home.homeDirectory}/.local/share/mise/shims"
      "${config.home.profileDirectory}/bin"
      "/nix/var/nix/profiles/default/bin"
      "${config.home.homeDirectory}/go/bin"
      "/usr/local/bin"
      "/opt/homebrew/bin"
      "/usr/bin"
      "/bin"
      "/usr/sbin"
      "/sbin"
    ]
    ++ lib.optional pkgs.stdenv.isLinux "/run/current-system/sw/bin"
  );

  serviceEnvironment =
    lib.mapAttrs (_: toString) config.home.sessionVariables
    // {
      HOME = config.home.homeDirectory;
      PATH = defaultPath;
    }
    // cfg.environment
    // {
      OPENCODE_CURSOR_AGENT_BRIDGE_PORT = port;
      OPENCODE_CURSOR_AGENT_BRIDGE_STANDALONE = "1";
    };

  bridgeRunner = pkgs.writeShellScript "cursor-agent-bridge" ''
    set -eu
    cd ${lib.escapeShellArg configDir}
    exec ${pkgs.bun}/bin/bun ${lib.escapeShellArg bridgeScript}
  '';

  serviceFingerprint = builtins.toJSON {
    inherit
      bridgeRunner
      bridgeScript
      port
      serviceEnvironment
      ;
    bun = "${pkgs.bun}/bin/bun";
    inherit host;
  };

  restartScript = serviceStartCommand: serviceRestartCommand: ''
    marker="${config.xdg.cacheHome}/dotfiles/cursor-agent-bridge.sha256"
    bridge="${bridgeScript}"
    url="${url}"
    label="${label}"
    systemdService="${systemdService}"

    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$marker")"

    new_hash=$(
      {
        printf '%s\n' ${lib.escapeShellArg serviceFingerprint}
        if [ -L "$bridge" ]; then
          ${pkgs.coreutils}/bin/readlink "$bridge"
        fi
        if [ -f "$bridge" ]; then
          ${pkgs.coreutils}/bin/sha256sum "$bridge"
        fi
      } | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -d' ' -f1
    )
    old_hash="$(${pkgs.coreutils}/bin/cat "$marker" 2>/dev/null || true)"

    health() {
      ${pkgs.curl}/bin/curl --fail --silent --max-time 1 "$url/v1/health" >/dev/null 2>&1
    }

    verify_service() {
      case "$(uname -s)" in
        Darwin)
          uid="$(id -u)"
          domain="gui/$uid"
          /bin/launchctl print "$domain/$label" 2>/dev/null | /usr/bin/grep -Eq "active count = [1-9][0-9]*"
          ;;
        Linux)
          if command -v systemctl >/dev/null 2>&1; then
            systemctl --user is-active --quiet "$systemdService"
            return $?
          fi
          return 1
          ;;
        *)
          return 1
          ;;
      esac
    }

    ready() {
      verify_service && health
    }

    wait_with_dots() {
      echo -n "==> Waiting for cursor-agent bridge at $url"
      for _ in $(${pkgs.coreutils}/bin/seq 1 200); do
        if ready; then
          echo " ok"
          return 0
        fi
        echo -n "."
        ${pkgs.coreutils}/bin/sleep 0.1
      done
      echo " failed"
      return 1
    }

    running_under_opencode_agent() {
      [ "''${AGENT:-}" = "1" ] || return 1
      [ "''${OPENCODE:-}" = "1" ] || [ -n "''${OPENCODE_RUN_ID:-}" ]
    }

    if [ "$new_hash" != "$old_hash" ]; then
      if running_under_opencode_agent && ready; then
        echo "==> Cursor Agent bridge inputs changed; restart deferred because setup is running under an OpenCode agent"
        echo "==> Run setup.sh from a normal shell to restart the bridge safely"
      else
        echo "==> Cursor Agent bridge inputs changed; restarting service"
        ${serviceRestartCommand}
        if wait_with_dots; then
          printf '%s\n' "$new_hash" > "$marker"
        else
          echo "warning: Cursor Agent bridge restart failed or did not become healthy at $url" >&2
          echo "==> Check logs: ${cfg.errorLogFile}" >&2
          echo "==> If port ${port} is occupied by an old bridge, kill it manually and rerun setup.sh" >&2
        fi
      fi
    elif ! ready; then
      echo "==> Cursor Agent bridge is not running; starting service"
      ${serviceStartCommand}
      if ! wait_with_dots; then
        echo "warning: Cursor Agent bridge start failed or did not become healthy at $url" >&2
        echo "==> Check logs: ${cfg.errorLogFile}" >&2
      fi
    fi
  '';
in
{
  options.programs.opencode.cursorAgentBridge = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run the local Cursor Agent OpenAI-compatible bridge as a
        Home Manager-managed user service. The OpenCode plugin file is
        still installed for the standalone entrypoint, but OpenCode
        client processes no longer bind the fixed provider port.
      '';
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/opencode/cursor-agent-bridge.log";
      description = "Path for Cursor Agent bridge stdout.";
    };

    errorLogFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/opencode/cursor-agent-bridge-error.log";
      description = "Path for Cursor Agent bridge stderr.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Extra environment variables for the Cursor Agent bridge service.
        Values override the stable PATH and Home Manager session variables.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.activation.opencodeCursorAgentBridgeLogDir =
          lib.hm.dag.entryBefore
            (
              [ "opencodeCursorAgentBridge" ]
              ++ lib.optional pkgs.stdenv.isDarwin "setupLaunchAgents"
              ++ lib.optional pkgs.stdenv.isLinux "reloadSystemd"
            )
            ''
              ${pkgs.coreutils}/bin/mkdir -p \
                "$(${pkgs.coreutils}/bin/dirname ${lib.escapeShellArg cfg.logFile})" \
                "$(${pkgs.coreutils}/bin/dirname ${lib.escapeShellArg cfg.errorLogFile})"
            '';
      }

      (lib.mkIf pkgs.stdenv.isDarwin {
        launchd.agents.${label} = {
          enable = true;
          config = {
            Label = label;
            ProgramArguments = [ "${bridgeRunner}" ];
            RunAtLoad = true;
            KeepAlive = true;
            WorkingDirectory = configDir;
            StandardOutPath = cfg.logFile;
            StandardErrorPath = cfg.errorLogFile;
            EnvironmentVariables = serviceEnvironment;
          };
        };

        home.activation.opencodeCursorAgentBridge =
          lib.hm.dag.entryAfter
            [
              "opencodeBunInstall"
              "setupLaunchAgents"
            ]
            (
              restartScript
                ''
                  uid="$(${pkgs.coreutils}/bin/id -u)"
                  domain="gui/$uid"
                  plist="${config.home.homeDirectory}/Library/LaunchAgents/${label}.plist"
                  if ! /bin/launchctl print "$domain/${label}" >/dev/null 2>&1 && [ -e "$plist" ]; then
                    /bin/launchctl bootstrap "$domain" "$plist" >/dev/null 2>&1 || true
                  fi
                  /bin/launchctl kickstart "$domain/${label}" >/dev/null 2>&1 || true
                ''
                ''
                  uid="$(${pkgs.coreutils}/bin/id -u)"
                  domain="gui/$uid"
                  plist="${config.home.homeDirectory}/Library/LaunchAgents/${label}.plist"
                  if ! /bin/launchctl print "$domain/${label}" >/dev/null 2>&1 && [ -e "$plist" ]; then
                    /bin/launchctl bootstrap "$domain" "$plist" >/dev/null 2>&1 || true
                  fi
                  /bin/launchctl kickstart -k "$domain/${label}" >/dev/null 2>&1 || \
                    /bin/launchctl kickstart "$domain/${label}" >/dev/null 2>&1 || true
                ''
            );
      })

      (lib.mkIf pkgs.stdenv.isLinux {
        systemd.user.services.opencode-cursor-agent-bridge = {
          Unit = {
            Description = "Cursor Agent OpenAI-compatible bridge";
            After = [ "network.target" ];
            StartLimitBurst = 5;
            StartLimitIntervalSec = 60;
          };
          Service = {
            ExecStart = "${bridgeRunner}";
            WorkingDirectory = configDir;
            Restart = "on-failure";
            RestartSec = 2;
            Environment = lib.mapAttrsToList (name: value: "${name}=${value}") serviceEnvironment;
            StandardOutput = "append:${cfg.logFile}";
            StandardError = "append:${cfg.errorLogFile}";
          };
          Install.WantedBy = [ "default.target" ];
        };

        home.activation.opencodeCursorAgentBridge =
          lib.hm.dag.entryAfter
            [
              "opencodeBunInstall"
              "reloadSystemd"
            ]
            (
              restartScript
                ''
                  if command -v systemctl >/dev/null 2>&1; then
                    systemctl --user start ${systemdService} >/dev/null 2>&1 || true
                  fi
                ''
                ''
                  if command -v systemctl >/dev/null 2>&1; then
                    systemctl --user restart ${systemdService} >/dev/null 2>&1 || true
                  fi
                ''
            );
      })
    ]
  );
}
