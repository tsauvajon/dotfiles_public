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
  serviceWorkingDirectory = config.home.homeDirectory;
  defaultPath = import ./lib/service-path.nix { inherit config lib pkgs; };

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
    cd ${lib.escapeShellArg serviceWorkingDirectory}
    exec ${pkgs.bun}/bin/bun ${lib.escapeShellArg bridgeScript}
  '';

  serviceFingerprint = builtins.toJSON {
    inherit
      bridgeRunner
      bridgeScript
      port
      serviceEnvironment
      serviceWorkingDirectory
      ;
    bun = "${pkgs.bun}/bin/bun";
    inherit host;
  };

  managedUserService = import ./lib/managed-user-service.nix { inherit config pkgs lib; };
in
{
  options.programs.opencode.cursorAgentBridge = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
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

  config = lib.mkIf cfg.enable (managedUserService {
    activationName = "opencodeCursorAgentBridge";
    activationAfter = [ "opencodeBunInstall" ];
    changedMessage = "Cursor Agent bridge inputs changed; restarting service";
    darwinProgramArguments = [ "${bridgeRunner}" ];
    deferredFollowup = "Run setup.sh from a normal shell to restart the bridge safely";
    deferredMessage = "Cursor Agent bridge inputs changed; restart deferred because setup is running under an OpenCode agent";
    description = "Cursor Agent OpenAI-compatible bridge";
    environment = serviceEnvironment;
    errorLogFile = cfg.errorLogFile;
    healthCommand = ''${pkgs.curl}/bin/curl --fail --silent --max-time 1 "$url/v1/health" >/dev/null 2>&1'';
    inherit
      label
      systemdService
      url
      serviceFingerprint
      ;
    linuxExecStart = "${bridgeRunner}";
    linuxRestartCommand = ''
      if command -v systemctl >/dev/null 2>&1; then
        systemctl --user restart ${systemdService} >/dev/null 2>&1 || true
      fi
    '';
    linuxService = {
      StandardOutput = "append:${cfg.logFile}";
      StandardError = "append:${cfg.errorLogFile}";
    };
    linuxUnit = {
      StartLimitBurst = 5;
      StartLimitIntervalSec = 60;
    };
    logFile = cfg.logFile;
    markerFile = "${config.xdg.cacheHome}/dotfiles/cursor-agent-bridge.sha256";
    occupiedHint = "If port ${port} is occupied by an old bridge, kill it manually and rerun setup.sh";
    restartFailureWarning = "Cursor Agent bridge restart failed or did not become healthy at $url";
    startFailureWarning = "Cursor Agent bridge start failed or did not become healthy at $url";
    systemdUnitName = "opencode-cursor-agent-bridge";
    waitAttempts = 200;
    waitDescription = "cursor-agent bridge";
    watchedPaths = [ bridgeScript ];
    workingDirectory = serviceWorkingDirectory;
  });
}
