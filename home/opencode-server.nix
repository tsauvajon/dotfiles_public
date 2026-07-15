{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.opencode.sharedServer;
  opencodePackage = pkgs.opencode;
  opencodeBin = "${opencodePackage}/bin/opencode";
  opBin = "${pkgs._1password-cli}/bin/op";
  port = toString cfg.port;
  url = "http://${cfg.host}:${port}";
  label = "dev.opencode.server";
  systemdService = "opencode-server.service";
  defaultPath = import ./lib/service-path.nix { inherit config lib pkgs; };
  onePasswordEnvFile = pkgs.writeText "opencode-onepassword-env" (
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: reference: "${name}=${reference}") cfg.onePasswordEnv
    )
    + "\n"
  );
  serveArguments = [
    opencodeBin
    "serve"
    "--hostname"
    cfg.host
    "--port"
    port
  ];
  serviceProgramArguments =
    if cfg.onePasswordEnv == { } then
      serveArguments
    else
      [
        opBin
        "run"
        "--env-file"
        "${onePasswordEnvFile}"
        "--"
      ]
      ++ serveArguments;

  serviceEnvironment =
    lib.mapAttrs (_: toString) config.home.sessionVariables
    // {
      HOME = config.home.homeDirectory;
      PATH = defaultPath;
    }
    // cfg.environment;

  serviceFingerprint = builtins.toJSON {
    inherit port serviceEnvironment serviceProgramArguments;
    host = cfg.host;
  };

  managedUserService = import ./lib/managed-user-service.nix { inherit config pkgs lib; };
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

    onePasswordEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Environment variables resolved through 1Password CLI secret
        references when the shared OpenCode server starts. Values are
        written as op:// references and resolved by `op run`, so the
        plaintext secrets are never stored in the generated launchd or
        systemd service definitions.
      '';
    };
  };

  config = lib.mkIf cfg.enable (managedUserService {
    activationName = "opencodeSharedServer";
    activationAfter = [ "opencodeBunInstall" ];
    changedMessage = "OpenCode shared server inputs changed; restarting service";
    darwinProgramArguments = serviceProgramArguments;
    deferredFollowup = "Run setup.sh from a normal shell to restart the shared server safely";
    deferredMessage = "OpenCode shared server inputs changed; restart deferred because setup is running under an OpenCode agent";
    description = "OpenCode shared local server";
    environment = serviceEnvironment;
    errorLogFile = cfg.errorLogFile;
    healthCommand = ''${pkgs.curl}/bin/curl --fail --silent --max-time 1 "$url/global/health" >/dev/null 2>&1'';
    inherit
      label
      systemdService
      url
      serviceFingerprint
      ;
    linuxExecStart = lib.escapeShellArgs serviceProgramArguments;
    linuxService.TimeoutStopSec = "15s";
    logFile = cfg.logFile;
    markerFile = "${config.xdg.cacheHome}/dotfiles/opencode-server.sha256";
    occupiedHint = "If port ${port} is occupied by an old server, kill it manually and rerun setup.sh";
    pendingRestart = {
      file = "${config.xdg.cacheHome}/dotfiles/opencode-server.pending-restart";
      reason = "setup is running under an OpenCode agent with a healthy server";
      fields.config_dir = "${config.xdg.configHome}/opencode";
    };
    restartFailureWarning = "OpenCode shared server restart failed or did not become healthy at $url";
    systemdUnitName = "opencode-server";
    waitAttempts = 100;
    waitDescription = "server";
    watchedPaths = [
      "${config.xdg.configHome}/opencode/opencode.json"
      "${config.xdg.configHome}/opencode/package.json"
      "${config.xdg.configHome}/opencode/plugins"
      "${config.xdg.configHome}/opencode/AGENTS.md"
    ];
    workingDirectory = config.home.homeDirectory;
  });
}
