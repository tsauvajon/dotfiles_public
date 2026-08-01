{ lib }:

let
  testLib = lib // {
    hm.dag = {
      entryAfter = deps: text: { inherit deps text; };
      entryBefore = deps: text: { inherit deps text; };
    };
    mkIf = condition: attrs: if condition then attrs else { };
    mkMerge = lib.foldl' lib.recursiveUpdate { };
  };

  mkPkgs =
    {
      isDarwin ? false,
      isLinux ? false,
    }:
    {
      stdenv = { inherit isDarwin isLinux; };
      coreutils = "/nix/store/coreutils";
      curl = "/nix/store/curl";
    };

  config = {
    home.homeDirectory = "/Users/example";
    xdg.cacheHome = "/Users/example/.cache";
  };

  mkService =
    pkgs:
    import ./managed-user-service.nix {
      inherit config pkgs;
      lib = testLib;
    };

  commonArgs = {
    activationName = "demoService";
    activationAfter = [ "dependency" ];
    changedMessage = "Demo inputs changed; restarting service";
    darwinProgramArguments = [ "/bin/demo" ];
    deferredMessage = "Demo inputs changed; restart deferred because setup is running under an OpenCode agent";
    description = "Demo service";
    environment = {
      HOME = "/Users/example";
      PATH = "/bin";
    };
    errorLogFile = "/Users/example/Library/Logs/demo.err";
    healthCommand = "/nix/store/curl/bin/curl --fail --silent http://127.0.0.1/health >/dev/null 2>&1";
    label = "dev.demo";
    linuxExecStart = "/bin/demo";
    logFile = "/Users/example/Library/Logs/demo.log";
    markerFile = "/Users/example/.cache/dotfiles/demo.sha256";
    restartFailureWarning = "Demo restart failed at $url";
    serviceFingerprint = ''{"demo":true}'';
    systemdService = "demo.service";
    systemdUnitName = "demo";
    url = "http://127.0.0.1:1234";
    waitAttempts = 42;
    waitDescription = "demo";
    watchedPaths = [ "/Users/example/.config/demo/config.json" ];
    workingDirectory = "/Users/example";
  };

  darwinOutput =
    (mkService (mkPkgs {
      isDarwin = true;
    }))
      commonArgs;
  linuxOutput =
    (mkService (mkPkgs {
      isLinux = true;
    }))
      commonArgs;
  pendingOutput =
    (mkService (mkPkgs {
      isDarwin = true;
    }))
      (
        commonArgs
        // {
          pendingRestart = {
            file = "/Users/example/.cache/dotfiles/demo.pending-restart";
            reason = "test deferral";
            fields.config_dir = "/Users/example/.config/demo";
          };
        }
      );
  noPendingScript = darwinOutput.home.activation.demoService.text;
  pendingScript = pendingOutput.home.activation.demoService.text;
in
{
  testDarwinLaunchdAgentShape = {
    expr = darwinOutput.launchd.agents."dev.demo".config;
    expected = {
      Label = "dev.demo";
      ProgramArguments = [ "/bin/demo" ];
      RunAtLoad = true;
      KeepAlive = true;
      WorkingDirectory = "/Users/example";
      StandardOutPath = "/Users/example/Library/Logs/demo.log";
      StandardErrorPath = "/Users/example/Library/Logs/demo.err";
      EnvironmentVariables = {
        HOME = "/Users/example";
        PATH = "/bin";
      };
    };
  };

  testLinuxSystemdUnitShape = {
    expr = linuxOutput.systemd.user.services.demo.Service;
    expected = {
      ExecStart = "/bin/demo";
      WorkingDirectory = "/Users/example";
      Restart = "on-failure";
      RestartSec = 2;
      Environment = [
        "HOME=/Users/example"
        "PATH=/bin"
      ];
    };
  };

  testLinuxServiceActionsPropagateFailures = {
    expr =
      let
        script = linuxOutput.home.activation.demoService.text;
      in
      (lib.hasInfix "systemctl --user start demo.service" script)
      && (lib.hasInfix "systemctl --user restart demo.service" script)
      && !(lib.hasInfix "systemctl --user start demo.service >/dev/null 2>&1 || true" script)
      && !(lib.hasInfix "systemctl --user restart demo.service >/dev/null 2>&1" script);
    expected = true;
  };

  testDarwinServiceActionsRemainUnchanged = {
    expr =
      let
        script = darwinOutput.home.activation.demoService.text;
      in
      (lib.hasInfix ''/bin/launchctl kickstart "$domain/${commonArgs.label}" >/dev/null 2>&1 || true'' script)
      && (lib.hasInfix ''/bin/launchctl kickstart -k "$domain/${commonArgs.label}" >/dev/null 2>&1 ||'' script);
    expected = true;
  };

  testMarkerAndWatchedPathAreEmbedded = {
    expr =
      (lib.hasInfix "demo.sha256" noPendingScript)
      && (lib.hasInfix "/Users/example/.config/demo/config.json" noPendingScript)
      && (lib.hasInfix ''printf '%s\n' "$new_hash" > "$marker"'' noPendingScript);
    expected = true;
  };

  testPendingRestartIsOptIn = {
    expr =
      !(lib.hasInfix "write_pending_restart" noPendingScript)
      && (lib.hasInfix "write_pending_restart" pendingScript)
      && (lib.hasInfix "demo.pending-restart" pendingScript)
      && (lib.hasInfix "config_dir=%s" pendingScript)
      && (lib.hasInfix "rm -f \"$pending_restart\"" pendingScript);
    expected = true;
  };

  testWaitDurationIsParameterized = {
    expr = lib.hasInfix "/nix/store/coreutils/bin/seq 1 42" noPendingScript;
    expected = true;
  };

  testActiveCountUsesStrictRegex = {
    expr = lib.hasInfix ''grep -Eq "active count = [1-9][0-9]*"'' noPendingScript;
    expected = true;
  };
}
