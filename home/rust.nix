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
  kacheBin = "${config.home.profileDirectory}/bin/kache";
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
    PATH = defaultPath;
  };
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
    launchd.agents.${kacheLabel} = {
      enable = true;
      config = {
        Label = kacheLabel;
        ProgramArguments = [
          kacheBin
          "daemon"
          "run"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        ThrottleInterval = 10;
        StandardOutPath = "${config.home.homeDirectory}/Library/Logs/kache.log";
        StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/kache-error.log";
        EnvironmentVariables = kacheEnvironment;
      };
    };
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
