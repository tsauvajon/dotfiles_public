# Rust development tools.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  stableRust = pkgs.rust-bin.stable.latest.default.override {
    extensions = [
      "clippy"
      "llvm-tools-preview"
      "rust-analyzer"
      "rust-src"
    ];
  };
  nightlyRustfmt = pkgs.rust-bin.selectLatestNightlyWith (
    toolchain:
    toolchain.default.override {
      extensions = [ "rustfmt" ];
    }
  );
  rustWithNightlyFmt = pkgs.symlinkJoin {
    name = "dotfiles-rust";
    paths = [
      pkgs.cargo-llvm-cov
      pkgs.grcov
      # Kept on PATH because kache delegates uncached invocations to sccache.
      pkgs.sccache
      stableRust
    ];
    postBuild = ''
      rm -f "$out/bin/rustfmt" "$out/bin/cargo-fmt"
      ln -s ${nightlyRustfmt}/bin/rustfmt "$out/bin/rustfmt"
      ln -s ${nightlyRustfmt}/bin/cargo-fmt "$out/bin/cargo-fmt"
    '';
  };
  kacheBin = lib.getExe pkgs.kache;
  kacheLabel = "ninja.kunobi.kache";
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
  kacheEnvironment = {
    HOME = config.home.homeDirectory;
    KACHE_CONFIG = "${config.xdg.configHome}/kache/config.toml";
    KACHE_LOG = "kache=info";
    PATH = defaultPath;
  };
  kacheLogDir = "${config.home.homeDirectory}/Library/Logs/kache";
  kachePlist = lib.generators.toPlist { escape = true; } {
    Label = kacheLabel;
    ProgramArguments = [
      kacheBin
      "daemon"
      "run"
    ];
    RunAtLoad = true;
    # Match upstream kache: failures restart, but `kache daemon stop` stays stopped.
    KeepAlive = {
      SuccessfulExit = false;
    };
    ThrottleInterval = 5;
    StandardOutPath = "${kacheLogDir}/out.log";
    StandardErrorPath = "${kacheLogDir}/err.log";
    EnvironmentVariables = kacheEnvironment;
  };
  kachePlistFile = pkgs.writeText "${kacheLabel}.plist" kachePlist;
in
lib.mkMerge [
  {
    # `cargo-nextest` ships separately so a private overlay can shadow
    # it (e.g. a private overlay may expose a vendored nextest with the same
    # binary name). `lib.lowPrio` makes the public copy lose the
    # buildEnv collision; without a competing definition it is used as
    # the only `cargo-nextest` on PATH.
    home.packages = [
      pkgs.cargo-coupling
      pkgs.cargo-outdated
      pkgs.kache
      pkgs.protobuf
      rustWithNightlyFmt
      (lib.lowPrio pkgs.cargo-nextest)
    ];

    xdg.configFile."kache/config.toml".text = ''
      [cache]
      fallback = "sccache"
    '';
  }

  (lib.mkIf pkgs.stdenv.isDarwin {
    home.activation.kacheDaemon =
      lib.hm.dag.entryAfter
        [
          "linkGeneration"
          "setupLaunchAgents"
        ]
        ''
          uid="$(${pkgs.coreutils}/bin/id -u)"
          domain="gui/$uid"
          label=${lib.escapeShellArg kacheLabel}
          plist=${lib.escapeShellArg "${config.home.homeDirectory}/Library/LaunchAgents/${kacheLabel}.plist"}
          plist_source=${lib.escapeShellArg kachePlistFile}
          log_dir=${lib.escapeShellArg kacheLogDir}

          ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$plist")" "$log_dir"
          if [ ! -e "$plist" ] || ! ${pkgs.diffutils}/bin/cmp -s "$plist_source" "$plist"; then
            ${pkgs.coreutils}/bin/install -m 0644 "$plist_source" "$plist"
            /bin/launchctl bootout "$domain/$label" >/dev/null 2>&1 || true
            if ! bootstrap_output="$(/bin/launchctl bootstrap "$domain" "$plist" 2>&1)"; then
              echo "warning: kache launchd bootstrap failed: $bootstrap_output" >&2
            fi
          elif ! /bin/launchctl print "$domain/$label" >/dev/null 2>&1; then
            if ! bootstrap_output="$(/bin/launchctl bootstrap "$domain" "$plist" 2>&1)"; then
              echo "warning: kache launchd bootstrap failed: $bootstrap_output" >&2
            fi
          fi
        '';
  })

  (lib.mkIf pkgs.stdenv.isLinux {
    systemd.user.services.kache = {
      Unit = {
        Description = "kache daemon";
        After = [ "network.target" ];
        StartLimitBurst = 5;
        StartLimitIntervalSec = 60;
      };
      Service = {
        ExecStart = "${kacheBin} daemon run";
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") kacheEnvironment;
        Restart = "on-failure";
        RestartSec = 2;
        Type = "simple";
      };
      Install.WantedBy = [ "default.target" ];
    };
  })
]
