# Rust development tools.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  stableRust = import ./lib/rust-toolchain.nix { inherit pkgs; };
  nightlyRustfmt = pkgs.rust-bin.selectLatestNightlyWith (
    toolchain:
    toolchain.default.override {
      extensions = [ "rustfmt" ];
    }
  );
  dylintToolchainDate = "2026-04-16";
  dylintToolchain = "nightly-${dylintToolchainDate}";
  dylintRust = pkgs.rust-bin.nightly.${dylintToolchainDate}.default.override {
    extensions = [
      "llvm-tools-preview"
      "rustc-dev"
      "rust-src"
      "rustfmt"
    ];
  };
  dylintLinkInputs = [ pkgs.zlib ] ++ lib.optionals pkgs.stdenv.isDarwin [ pkgs.libiconv ];
  dylintLinkLibraryPath = lib.makeLibraryPath dylintLinkInputs;
  dylintToolchainWithTarget = "${dylintToolchain}-${pkgs.stdenv.hostPlatform.rust.rustcTarget}";
  dylintShims = pkgs.symlinkJoin {
    name = "dotfiles-dylint-shims";
    paths = [
      (pkgs.writeShellScriptBin "rustup" ''
        set -euo pipefail

        case "$*" in
          "+stable which cargo"|"which cargo")
            printf '%s\n' "${dylintRust}/bin/cargo"
            ;;
          "which rustc")
            printf '%s\n' "${dylintRust}/bin/rustc"
            ;;
          "show active-toolchain")
            printf '%s (provided by Nix)\n' "${dylintToolchainWithTarget}"
            ;;
          *)
            printf 'rustup shim only supports Dylint toolchain queries, got: rustup %s\n' "$*" >&2
            exit 1
            ;;
        esac
      '')
      (pkgs.writeShellScriptBin "cargo" ''
        export RUSTUP_TOOLCHAIN="${dylintToolchainWithTarget}"
        export RUSTC="${dylintRust}/bin/rustc"
        export CARGO_BUILD_RUSTC_WRAPPER=
        unset RUSTC_WRAPPER
        export LIBRARY_PATH="${dylintLinkLibraryPath}:''${LIBRARY_PATH:-}"
        export PATH="${dylintRust}/bin:$PATH"
        exec "${dylintRust}/bin/cargo" "$@"
      '')
    ];
  };
  dylintCargo = pkgs.writeShellScriptBin "dylint-cargo" ''
    export RUSTUP_TOOLCHAIN="${dylintToolchainWithTarget}"
    export RUSTC="${dylintRust}/bin/rustc"
    export CARGO_BUILD_RUSTC_WRAPPER=
    unset RUSTC_WRAPPER
    export LIBRARY_PATH="${dylintLinkLibraryPath}:''${LIBRARY_PATH:-}"
    export PATH="${dylintRust}/bin:$PATH"
    exec "${dylintRust}/bin/cargo" "$@"
  '';
  dylintTools = pkgs.symlinkJoin {
    name = "dotfiles-dylint-tools";
    paths = [
      pkgs.dylint-tools
      dylintCargo
    ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/cargo-dylint" \
        --set DYLINT_RUST_BIN "${dylintRust}/bin" \
        --set DYLINT_RUSTUP_BIN "${dylintShims}/bin" \
        --set CARGO_BUILD_RUSTC_WRAPPER "" \
        --unset RUSTC_WRAPPER \
        --prefix PATH : "${dylintShims}/bin:${dylintRust}/bin" \
        --prefix LIBRARY_PATH : "${dylintLinkLibraryPath}"
      wrapProgram "$out/bin/dylint-link" \
        --prefix LIBRARY_PATH : "${dylintLinkLibraryPath}"
    '';
  };
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
  kacheLocalMaxSize = "300GiB";
  defaultPath = import ./lib/service-path.nix { inherit config lib pkgs; };
  kacheEnvironment = {
    HOME = config.home.homeDirectory;
    KACHE_CONFIG = "${config.xdg.configHome}/kache/config.toml";
    KACHE_DAEMON_IDLE_TIMEOUT = "0";
    KACHE_LOG = "kache=info";
    # Keep this in the daemon environment so macOS plist changes restart stale daemons.
    KACHE_MAX_SIZE = kacheLocalMaxSize;
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
      dylintTools
      pkgs.kache
      pkgs.protobuf
      rustWithNightlyFmt
      (lib.lowPrio pkgs.cargo-nextest)
    ];

    xdg.configFile."kache/config.toml".text = ''
      [cache]
      fallback = "sccache"
      local_max_size = "${kacheLocalMaxSize}"
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
            HOME=${lib.escapeShellArg config.home.homeDirectory} KACHE_CONFIG=${lib.escapeShellArg "${config.xdg.configHome}/kache/config.toml"} ${kacheBin} daemon stop >/dev/null 2>&1 || true
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
        ExecStop = "${kacheBin} daemon stop";
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") kacheEnvironment;
        KillSignal = "SIGKILL";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStopSec = "5s";
        Type = "simple";
      };
      Install.WantedBy = [ "default.target" ];
    };
  })
]
