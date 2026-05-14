{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.opencode.sharedServer;
  opencodePackage = inputs.opencode.packages.${pkgs.stdenv.system}.opencode;
  opencodeBin = "${opencodePackage}/bin/opencode";
  port = toString cfg.port;
  url = "http://${cfg.host}:${port}";
  label = "dev.opencode.server";
  systemdService = "opencode-server.service";

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
      PATH = defaultPath;
    }
    // cfg.environment;

  serviceFingerprint = builtins.toJSON {
    inherit opencodeBin port serviceEnvironment;
    host = cfg.host;
  };

  restartScript = serviceStartCommand: serviceRestartCommand: ''
    marker="${config.xdg.cacheHome}/dotfiles/opencode-server.sha256"
    config_dir="${config.xdg.configHome}/opencode"
    url="${url}"

    ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$marker")"

    new_hash=$(
      {
        printf '%s\n' ${lib.escapeShellArg serviceFingerprint}
        for path in \
          "$config_dir/opencode.json" \
          "$config_dir/package.json" \
          "$config_dir/plugins" \
          "$config_dir/AGENTS.md"
        do
          if [ -L "$path" ]; then
            ${pkgs.coreutils}/bin/readlink "$path"
          fi
          if [ -f "$path" ]; then
            ${pkgs.coreutils}/bin/sha256sum "$path"
          fi
        done
      } | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -d' ' -f1
    )
    old_hash="$(${pkgs.coreutils}/bin/cat "$marker" 2>/dev/null || true)"

    health() {
      ${pkgs.curl}/bin/curl --fail --silent --max-time 1 "$url/global/health" >/dev/null 2>&1
    }

    wait_for_health() {
      for _ in $(${pkgs.coreutils}/bin/seq 1 50); do
        if health; then
          return 0
        fi
        ${pkgs.coreutils}/bin/sleep 0.1
      done

      return 1
    }

    running_under_opencode_agent() {
      [ "''${AGENT:-}" = "1" ] || return 1
      [ "''${OPENCODE:-}" = "1" ] || [ -n "''${OPENCODE_RUN_ID:-}" ]
    }

    if [ "$new_hash" != "$old_hash" ]; then
      if running_under_opencode_agent; then
        echo "==> OpenCode shared server inputs changed; restart deferred because setup is running under an OpenCode agent"
        echo "==> Run setup.sh from a normal shell to restart the shared server safely"
      else
        echo "==> OpenCode shared server inputs changed; restarting service"
        ${serviceRestartCommand}
        if wait_for_health; then
          printf '%s\n' "$new_hash" > "$marker"
        else
          echo "warning: OpenCode shared server did not become healthy at $url after restart" >&2
        fi
      fi
    elif ! health; then
      echo "==> OpenCode shared server is not running; starting service"
      ${serviceStartCommand}
    fi
  '';
in
{
  options.programs.opencode.sharedServer = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Run the shared local OpenCode server as a Home Manager-managed
        user service. The shell wrapper then attaches to this service
        instead of spawning an unmanaged background process.
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host for the shared OpenCode server.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4096;
      description = "Port for the shared OpenCode server.";
    };

    logFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/opencode/shared-server.log";
      description = "Path for shared OpenCode server stdout.";
    };

    errorLogFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.xdg.dataHome}/opencode/shared-server-error.log";
      description = "Path for shared OpenCode server stderr.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Extra environment variables for the shared OpenCode server.
        Values override the stable PATH and Home Manager session
        variables supplied by this module.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        home.activation.opencodeSharedServerLogDir =
          lib.hm.dag.entryBefore
            (
              [ "opencodeSharedServer" ]
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
            ProgramArguments = [
              opencodeBin
              "serve"
              "--hostname"
              cfg.host
              "--port"
              port
            ];
            RunAtLoad = true;
            KeepAlive = true;
            WorkingDirectory = config.home.homeDirectory;
            StandardOutPath = cfg.logFile;
            StandardErrorPath = cfg.errorLogFile;
            EnvironmentVariables = serviceEnvironment;
          };
        };

        home.activation.opencodeSharedServer =
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
        systemd.user.services.opencode-server = {
          Unit = {
            Description = "OpenCode shared local server";
            After = [ "network.target" ];
          };
          Service = {
            ExecStart = "${opencodeBin} serve --hostname ${cfg.host} --port ${port}";
            WorkingDirectory = config.home.homeDirectory;
            Restart = "on-failure";
            RestartSec = 2;
            Environment = lib.mapAttrsToList (name: value: "${name}=${value}") serviceEnvironment;
          };
          Install.WantedBy = [ "default.target" ];
        };

        home.activation.opencodeSharedServer =
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
                    systemctl --user restart ${systemdService} >/dev/null 2>&1 || \
                      systemctl --user start ${systemdService} >/dev/null 2>&1 || true
                  fi
                ''
            );
      })
    ]
  );
}
