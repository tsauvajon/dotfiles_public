{
  description = "Steel-enabled Helix with pinned plugins";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    helix-steel = {
      url = "github:mattwparas/helix/steel-event-system";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };
    steel = {
      url = "github:mattwparas/steel/605d490c07ae6937d532d5a994920b4dab3016ad";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    scooter-hx = {
      url = "github:thomasschafer/scooter.hx/v0.1.4";
      flake = false;
    };
    fake-warp-hx = {
      url = "github:Xerxes-2/fake-warp.hx/542214f6359880c70663e3e58e0d1c5fda10d328";
      flake = false;
    };
    smooth-scroll-hx = {
      url = "github:thomasschafer/smooth-scroll.hx/1ed8b088e465fb139389c36ad158ba4a2d9e1bbc";
      flake = false;
    };
    helix-file-watcher = {
      url = "github:mattwparas/helix-file-watcher/e36434634b0a862280dc832921c9aa0d62198964";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
      helix-steel,
      steel,
      scooter-hx,
      fake-warp-hx,
      smooth-scroll-hx,
      helix-file-watcher,
    }:
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-darwin"
      ]
      (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [ rust-overlay.overlays.default ];
          };
          stableRust = pkgs.rust-bin.stable.latest.default.override {
            extensions = [ "rust-src" ];
          };
          helixWithSteel = (helix-steel.packages.${system}.default).overrideAttrs (old: {
            cargoBuildFlags = (old.cargoBuildFlags or [ ]) ++ [
              "--features"
              "steel"
            ];
            cargoCheckFlags = (old.cargoCheckFlags or [ ]) ++ [
              "--features"
              "steel"
            ];
            cargoInstallFlags = (old.cargoInstallFlags or [ ]) ++ [
              "--features"
              "steel"
            ];
          });
          steelPkg = steel.packages.${system}.steel;
          dylibExt = if pkgs.stdenv.isDarwin then "dylib" else "so";
          copyPluginDirs =
            src: name: dirs:
            pkgs.lib.concatMapStringsSep "\n" (dir: ''
              cp -R "${src}/${dir}" "$out/lib/steel/cogs/${name}/${dir}"
            '') dirs;
          mkSchemePlugin =
            {
              name,
              src,
              extraDirs ? [ ],
            }:
            pkgs.runCommand "helix-plugin-${name}" { } ''
              mkdir -p "$out/lib/steel/cogs/${name}"
              cp -R ${src}/*.scm "$out/lib/steel/cogs/${name}/"
              ${copyPluginDirs src name extraDirs}
            '';
          mkRustPlugin =
            {
              name,
              src,
              libName,
              cargoHash ? null,
              cargoLock ? null,
              extraDirs ? [ ],
              postPatch ? "",
            }:
            pkgs.rustPlatform.buildRustPackage (
              {
                pname = "helix-plugin-${name}";
                version = "unstable";
                inherit src postPatch;

                doCheck = false;

                installPhase = ''
                  runHook preInstall

                  mkdir -p "$out/lib/steel/cogs/${name}"
                  mkdir -p "$out/lib/steel/native"

                  cp -R *.scm "$out/lib/steel/cogs/${name}/"
                  ${copyPluginDirs src name extraDirs}

                  if [ -f "target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/release/lib${libName}.${dylibExt}" ]; then
                    install -m 0755 \
                      "target/${pkgs.stdenv.hostPlatform.rust.rustcTarget}/release/lib${libName}.${dylibExt}" \
                      "$out/lib/steel/native/lib${libName}.${dylibExt}"
                  else
                    install -m 0755 \
                      "target/release/lib${libName}.${dylibExt}" \
                      "$out/lib/steel/native/lib${libName}.${dylibExt}"
                  fi

                  runHook postInstall
                '';
              }
              // (
                if cargoLock != null then
                  {
                    cargoLock = {
                      lockFile = cargoLock;
                      allowBuiltinFetchGit = true;
                    };
                  }
                else
                  { inherit cargoHash; }
              )
            );
          fakeWarpPlugin = mkSchemePlugin {
            name = "fake-warp";
            src = fake-warp-hx;
          };
          smoothScrollPlugin = mkSchemePlugin {
            name = "smooth-scroll";
            src = smooth-scroll-hx;
            extraDirs = [ "src" ];
          };
          scooterPlugin = mkRustPlugin {
            name = "scooter";
            src = scooter-hx;
            libName = "scooter_hx";
            cargoLock = scooter-hx + "/Cargo.lock";
            extraDirs = [ "ui" ];
          };
          fileWatcherPlugin = mkRustPlugin {
            name = "helix-file-watcher";
            src = helix-file-watcher;
            libName = "helix_file_watcher";
            cargoLock = ./cargo-locks/helix-file-watcher.Cargo.lock;
            postPatch = ''
              cp ${./cargo-locks/helix-file-watcher.Cargo.lock} Cargo.lock
              substituteInPlace Cargo.toml \
                --replace-fail \
                'git = "https://github.com/mattwparas/steel.git"' \
                'git = "https://github.com/mattwparas/steel.git", rev = "605d490c07ae6937d532d5a994920b4dab3016ad"'
            '';
          };
          helixSteelHome = pkgs.symlinkJoin {
            name = "helix-steel-home";
            paths = [
              steelPkg
              fakeWarpPlugin
              smoothScrollPlugin
              scooterPlugin
              fileWatcherPlugin
            ];
          };
          helixPlugins = pkgs.symlinkJoin {
            name = "helix-with-steel-plugins";
            paths = [
              helixWithSteel
              steelPkg
            ];
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram "$out/bin/hx" \
                --run 'export STEEL_HOME="''${STEEL_HOME:-''${XDG_DATA_HOME:-$HOME/.local/share}/steel}"' \
                --run 'mkdir -p "$STEEL_HOME"' \
                --run 'mkdir -p "$STEEL_HOME/native"' \
                --run 'for dylib in "${helixSteelHome}/lib/steel/native"/*; do dest="$STEEL_HOME/native/$(basename "$dylib")"; if [ -L "$dest" ]; then rm "$dest"; fi; if [ ! -e "$dest" ]; then ln -s "$dylib" "$dest"; fi; done' \
                --prefix STEEL_SEARCH_PATHS : "${helixSteelHome}/lib/steel/cogs" \
                --prefix PATH : ${
                  pkgs.lib.makeBinPath [
                    steelPkg
                    stableRust
                    pkgs.git
                  ]
                }
            '';
          };
        in
        {
          packages = {
            helix-plugins = helixPlugins;
            default = self.packages.${system}.helix-plugins;
          };

          devShells.default = pkgs.mkShell {
            packages = [
              helixPlugins
              stableRust
            ];
          };

          formatter = pkgs.nixfmt;
        }
      );
}
