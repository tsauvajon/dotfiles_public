{
  config,
  pkgs,
  lib,
}:

let
  mkWatchedPathHashSnippet =
    watchedPaths:
    lib.concatMapStringsSep "\n" (path: ''
      path=${lib.escapeShellArg path}
      if [ -L "$path" ]; then
        ${pkgs.coreutils}/bin/readlink "$path"
      fi
      if [ -f "$path" ]; then
        ${pkgs.coreutils}/bin/sha256sum "$path"
      fi
    '') watchedPaths;

  mkPendingFieldSnippet =
    fields:
    lib.concatMapStringsSep "\n" (name: ''
      printf '${name}=%s\n' ${lib.escapeShellArg fields.${name}}
    '') (builtins.attrNames fields);
in
{
  activationName,
  darwinProgramArguments,
  description,
  environment,
  errorLogFile,
  healthCommand,
  label,
  linuxExecStart,
  logFile,
  markerFile,
  serviceFingerprint,
  systemdService,
  systemdUnitName,
  url,
  waitAttempts,
  waitDescription,
  watchedPaths,
  workingDirectory,
  activationAfter ? [ ],
  changedMessage,
  darwinAgentConfig ? { },
  deferredFollowup ? null,
  deferredMessage,
  linuxService ? { },
  linuxRestartCommand ? null,
  linuxStartCommand ? null,
  linuxUnit ? { },
  occupiedHint ? null,
  pendingRestart ? null,
  restartFailureWarning,
  startFailureWarning ? null,
}:

let
  logDirActivationName = "${activationName}LogDir";
  hasPendingRestart = pendingRestart != null;
  pendingRestartFieldSnippet =
    if hasPendingRestart then mkPendingFieldSnippet (pendingRestart.fields or { }) else "";
  removePendingRestartSnippet = lib.optionalString hasPendingRestart ''
    ${pkgs.coreutils}/bin/rm -f "$pending_restart"
  '';
  writePendingRestartFunction = lib.optionalString hasPendingRestart ''

        write_pending_restart() {
          {
            printf 'reason=%s\n' ${lib.escapeShellArg pendingRestart.reason}
            printf 'url=%s\n' "$url"
            printf 'old_hash=%s\n' "$old_hash"
            printf 'new_hash=%s\n' "$new_hash"
            printf 'marker=%s\n' "$marker"
    ${pendingRestartFieldSnippet}
            ${pkgs.coreutils}/bin/date -u '+created_at=%Y-%m-%dT%H:%M:%SZ'
          } > "$pending_restart"
        }
  '';
  writePendingRestartCall = lib.optionalString hasPendingRestart ''
    write_pending_restart
  '';
  pendingRestartVar = lib.optionalString hasPendingRestart ''
    pending_restart=${lib.escapeShellArg pendingRestart.file}
  '';
  deferredFollowupEcho = lib.optionalString (deferredFollowup != null) ''
    echo "==> ${deferredFollowup}"
  '';
  occupiedHintEcho = lib.optionalString (occupiedHint != null) ''
    echo "==> ${occupiedHint}" >&2
  '';
  startFailureEcho = lib.optionalString (startFailureWarning != null) ''
    else
      echo "warning: ${startFailureWarning}" >&2
      echo "==> Check logs: ${errorLogFile}" >&2
  '';

  restartScript = serviceStartCommand: serviceRestartCommand: ''
        marker=${lib.escapeShellArg markerFile}
    ${pendingRestartVar}    url=${lib.escapeShellArg url}
        label=${lib.escapeShellArg label}
        systemdService=${lib.escapeShellArg systemdService}

        ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$marker")"

        new_hash=$(
          {
            printf '%s\n' ${lib.escapeShellArg serviceFingerprint}
    ${mkWatchedPathHashSnippet watchedPaths}
          } | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -d' ' -f1
        )
        old_hash="$(${pkgs.coreutils}/bin/cat "$marker" 2>/dev/null || true)"

        health() {
          ${healthCommand}
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
          echo -n "==> Waiting for ${waitDescription} at $url"
          for _ in $(${pkgs.coreutils}/bin/seq 1 ${toString waitAttempts}); do
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
    ${writePendingRestartFunction}

        running_under_opencode_agent() {
          [ "''${AGENT:-}" = "1" ] || return 1
          [ "''${OPENCODE:-}" = "1" ] || [ -n "''${OPENCODE_RUN_ID:-}" ]
        }

        if [ "$new_hash" != "$old_hash" ]; then
          if running_under_opencode_agent && ready; then
    ${writePendingRestartCall}        echo "==> ${deferredMessage}"
    ${deferredFollowupEcho}      else
            echo "==> ${changedMessage}"
            ${serviceRestartCommand}
            if wait_with_dots; then
              printf '%s\n' "$new_hash" > "$marker"
    ${removePendingRestartSnippet}        else
              echo "warning: ${restartFailureWarning}" >&2
              echo "==> Check logs: ${errorLogFile}" >&2
    ${occupiedHintEcho}        fi
          fi
        elif ! ready; then
          echo "==> ${waitDescription} is not running; starting service"
          ${serviceStartCommand}
          if wait_with_dots; then
    ${removePendingRestartSnippet}        true
    ${startFailureEcho}      fi
        else
    ${removePendingRestartSnippet}      true
        fi
  '';

  darwinStartCommand = ''
    uid="$(${pkgs.coreutils}/bin/id -u)"
    domain="gui/$uid"
    plist="${config.home.homeDirectory}/Library/LaunchAgents/${label}.plist"
    if ! /bin/launchctl print "$domain/${label}" >/dev/null 2>&1 && [ -e "$plist" ]; then
      /bin/launchctl bootstrap "$domain" "$plist" >/dev/null 2>&1 || true
    fi
    /bin/launchctl kickstart "$domain/${label}" >/dev/null 2>&1 || true
  '';

  darwinRestartCommand = ''
    uid="$(${pkgs.coreutils}/bin/id -u)"
    domain="gui/$uid"
    plist="${config.home.homeDirectory}/Library/LaunchAgents/${label}.plist"
    if ! /bin/launchctl print "$domain/${label}" >/dev/null 2>&1 && [ -e "$plist" ]; then
      /bin/launchctl bootstrap "$domain" "$plist" >/dev/null 2>&1 || true
    fi
    /bin/launchctl kickstart -k "$domain/${label}" >/dev/null 2>&1 || \
      /bin/launchctl kickstart "$domain/${label}" >/dev/null 2>&1 || true
  '';

  defaultLinuxStartCommand = ''
    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user start ${systemdService}
    else
      echo "error: systemctl is required to start ${systemdService}" >&2
      false
    fi
  '';

  defaultLinuxRestartCommand = ''
    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user restart ${systemdService}
    else
      echo "error: systemctl is required to restart ${systemdService}" >&2
      false
    fi
  '';
  effectiveLinuxStartCommand =
    if linuxStartCommand == null then defaultLinuxStartCommand else linuxStartCommand;
  effectiveLinuxRestartCommand =
    if linuxRestartCommand == null then defaultLinuxRestartCommand else linuxRestartCommand;
in
lib.mkMerge [
  {
    home.activation.${logDirActivationName} =
      lib.hm.dag.entryBefore
        (
          [ activationName ]
          ++ lib.optional pkgs.stdenv.isDarwin "setupLaunchAgents"
          ++ lib.optional pkgs.stdenv.isLinux "reloadSystemd"
        )
        ''
          ${pkgs.coreutils}/bin/mkdir -p \
            "$(${pkgs.coreutils}/bin/dirname ${lib.escapeShellArg logFile})" \
            "$(${pkgs.coreutils}/bin/dirname ${lib.escapeShellArg errorLogFile})"
        '';
  }

  (lib.mkIf pkgs.stdenv.isDarwin {
    launchd.agents.${label} = {
      enable = true;
      config = {
        Label = label;
        ProgramArguments = darwinProgramArguments;
        RunAtLoad = true;
        KeepAlive = true;
        WorkingDirectory = workingDirectory;
        StandardOutPath = logFile;
        StandardErrorPath = errorLogFile;
        EnvironmentVariables = environment;
      }
      // darwinAgentConfig;
    };

    home.activation.${activationName} = lib.hm.dag.entryAfter (
      activationAfter ++ [ "setupLaunchAgents" ]
    ) (restartScript darwinStartCommand darwinRestartCommand);
  })

  (lib.mkIf pkgs.stdenv.isLinux {
    systemd.user.services.${systemdUnitName} = {
      Unit = {
        Description = description;
        After = [ "network.target" ];
      }
      // linuxUnit;
      Service = {
        ExecStart = linuxExecStart;
        WorkingDirectory = workingDirectory;
        Restart = "on-failure";
        RestartSec = 2;
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") environment;
      }
      // linuxService;
      Install.WantedBy = [ "default.target" ];
    };

    home.activation.${activationName} = lib.hm.dag.entryAfter (activationAfter ++ [ "reloadSystemd" ]) (
      restartScript effectiveLinuxStartCommand effectiveLinuxRestartCommand
    );
  })
]
