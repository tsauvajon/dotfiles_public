{
  description = "Thomas's dotfiles";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-utils.url = "github:numtide/flake-utils";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # nixGL pinned alongside a known-good nixpkgs commit. Touching the
    # pin will likely break OpenGL on Linux.
    nixgl.url = "github:nix-community/nixGL";
    nixgl-nixpkgs.url = "github:nixos/nixpkgs/93e8cdce7afc64297cfec447c311470788131cd9";

    # Helix Steel and pinned plugin sources.
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

    # Private overlay flake: machine-local secrets, identity, and private
    # OpenCode commands/skills/agents/plugins/rules.
    #
    # Uses a pure placeholder by default; override at build time with:
    #   --override-input private ~/.config/dotfiles
    private = {
      url = "path:./private-placeholder";
      flake = true;
    };

    # goto and task are consumed as upstream flakes that expose their
    # own homeManagerModules.
    goto = {
      url = "github:tsauvajon/goto";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
    task = {
      url = "github:tsauvajon/task";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.rust-overlay.follows = "rust-overlay";
    };

    # Catppuccin theme content sourced from upstream flakes. The
    # catppuccin/nix metaflake covers most tools; fzf, zellij, and the
    # raw palette JSON are pinned as source repos directly.
    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Source-only palette so home/files.nix can read palette.json without
    # forcing an import-from-derivation on a system-specific catppuccin
    # build (which previously broke pure cross-system eval).
    catppuccin-palette = {
      url = "github:catppuccin/palette";
      flake = false;
    };
    catppuccin-fzf = {
      url = "github:catppuccin/fzf";
      flake = false;
    };
    catppuccin-zellij = {
      url = "github:catppuccin/zellij";
      flake = false;
    };
    catppuccin-yazi = {
      url = "github:catppuccin/yazi";
      flake = false;
    };
    yazi-plugins = {
      url = "github:yazi-rs/plugins";
      flake = false;
    };
    catppuccin-bat = {
      url = "github:catppuccin/bat";
      flake = false;
    };
    catppuccin-opencode = {
      url = "github:catppuccin/opencode";
      flake = false;
    };

    # ddcctl: macOS DDC/CI monitor control. Only used on x86_64-darwin
    # (Apple Silicon uses pkgs.m1ddc from nixpkgs). Pinned to a specific
    # commit because upstream is in self-described maintenance mode.
    ddcctl-src = {
      url = "github:kfix/ddcctl/06c7ab6eba5b1c903678f8113a92cef990acaf90";
      flake = false;
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      home-manager,
      rust-overlay,
      ...
    }:
    let
      opencodePin = {
        version = "1.15.5";
        srcHash = "sha256-HZiqia9QzkJMfRQ6bzFBsiGXNHv1WFLUdwhekE+rXM8=";
        nodeModulesHash = "sha256-lxwxaFTgonMPIe2GweEVZhCMSUN/quBgV1wvV05U5wc=";
      };
      opencodePackageJson = builtins.fromJSON (builtins.readFile ./config/opencode/package.json);

      localOverlay =
        system: final: prev:
        let
          opencodeSrc = final.fetchFromGitHub {
            owner = "anomalyco";
            repo = "opencode";
            tag = "v${opencodePin.version}";
            hash = opencodePin.srcHash;
          };
        in
        {
          cargo-coupling = final.callPackage ./pkgs/cargo-coupling { };
          glim = final.callPackage ./pkgs/glim { };
          kache = final.callPackage ./pkgs/kache { };
          sem = final.callPackage ./pkgs/sem { };
          tsql = final.callPackage ./pkgs/tsql { };
          weave = final.callPackage ./pkgs/weave { };

          opencode = prev.opencode.overrideAttrs (
            old:
            assert final.lib.assertMsg (
              old ? env && builtins.isAttrs old.env
            ) "pkgs.opencode.env is not an attrset";
            assert final.lib.assertMsg (old ? node_modules) "pkgs.opencode has no node_modules derivation";
            {
              version = opencodePin.version;
              src = opencodeSrc;

              node_modules = old.node_modules.overrideAttrs (_: {
                version = opencodePin.version;
                src = opencodeSrc;
                outputHash = opencodePin.nodeModulesHash;
              });

              env = old.env // {
                OPENCODE_VERSION = opencodePin.version;
                OPENCODE_CHANNEL = "stable";
              };

              meta =
                (old.meta or { })
                // final.lib.optionalAttrs (system == "x86_64-darwin") {
                  badPlatforms = builtins.filter (
                    platform: !(final.lib.meta.platformMatch { system = "x86_64-darwin"; } platform)
                  ) (old.meta.badPlatforms or [ ]);
                };
            }
          );

          # Apply a downstream patch to harper that suppresses the
          # SentenceCapitalization lint inside markdown list items, since
          # upstream issue #189 was closed as not planned.
          harper = prev.harper.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [
              ./pkgs/harper/skip-list-capitalization.patch
            ];
          });
        };

      mkPkgs =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            rust-overlay.overlays.default
            (localOverlay system)
          ];
        };

      dotfilesRoot = ./.;

      mkHome =
        {
          system,
          hostModule,
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs system;
          extraSpecialArgs = { inherit inputs system dotfilesRoot; };
          modules = [
            ./home
            hostModule
          ]
          ++ (inputs.private.homeModules or [ ]);
        };

      homeConfigurations = {
        thomas-darwin = mkHome {
          system = "aarch64-darwin";
          hostModule = ./home/hosts/darwin.nix;
        };
        thomas-darwin-intel = mkHome {
          system = "x86_64-darwin";
          hostModule = ./home/hosts/darwin.nix;
        };
        thomas-linux = mkHome {
          system = "x86_64-linux";
          hostModule = ./home/hosts/linux.nix;
        };
      };
    in
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ]
      (
        system:
        let
          pkgs = mkPkgs system;
          inherit (pkgs) lib;
          # Map each host to the system it targets so `nix flake check
          # --all-systems` exercises every homeConfiguration. Pure
          # evaluation alone catches issues like the nixGL fetchurl
          # regression; building still requires the matching system or
          # a remote builder.
          hostsForSystem = {
            "aarch64-darwin" = [ "thomas-darwin" ];
            "x86_64-darwin" = [ "thomas-darwin-intel" ];
            "x86_64-linux" = [ "thomas-linux" ];
          };
          hosts = hostsForSystem.${system} or [ ];

          # Pure value-equality unit tests for the lib helpers. Each
          # imported file returns an attrset of `{expr; expected;}`
          # cases; we union them and feed the union to `lib.runTests`.
          # `runTests` returns `[]` on success or a list of failed
          # cases, which we convert into a 0/non-zero exit by writing
          # `$out` only when the list is empty.
          libRunTestsCases =
            (import ./home/lib/deep-merge-json.test.nix { inherit lib; })
            // (import ./home/lib/concat-files.test.nix { inherit lib; })
            // (import ./home/lib/list-files-in.test.nix { inherit lib; })
            // (import ./home/default.test.nix { inherit lib; })
            // (import ./home/bootstrap.test.nix { inherit lib; })
            // (import ./home/programs/cross-shell-aliases.test.nix { inherit lib; });
          libRunTestsFailures = lib.runTests libRunTestsCases;
          libRunTestsCheck = pkgs.runCommand "lib-runTests" { } (
            if libRunTestsFailures == [ ] then
              ''
                echo "lib runTests: all ${toString (builtins.length (builtins.attrNames libRunTestsCases))} cases passed"
                touch "$out"
              ''
            else
              ''
                echo "lib runTests failures:" >&2
                cat <<'EOF' >&2
                ${builtins.toJSON libRunTestsFailures}
                EOF
                exit 1
              ''
          );

          mergeDirsCheck = import ./home/lib/merge-dirs.test.nix { inherit pkgs lib; };
          opencodeTestsCheck = import ./home/opencode.test { inherit pkgs lib; };
          opencodeVersionAlignmentCheck =
            pkgs.runCommand "opencode-version-alignment"
              {
                expectedVersion = opencodePin.version;
                packageVersion = pkgs.opencode.version;
                pluginVersion = opencodePackageJson.dependencies."@opencode-ai/plugin";
              }
              ''
                if [ "$packageVersion" != "$expectedVersion" ]; then
                  echo "pkgs.opencode is $packageVersion, expected $expectedVersion" >&2
                  exit 1
                fi

                if [ "$pluginVersion" != "$expectedVersion" ]; then
                  echo "@opencode-ai/plugin is $pluginVersion, expected $expectedVersion" >&2
                  exit 1
                fi

                touch "$out"
              '';
          patchStringFieldCheck = import ./scripts/lib/patch-empty-string-field.test.nix {
            inherit pkgs lib;
          };
          gpgPinentryCheck = import ./scripts/lib/configure-gpg-pinentry.test.nix { inherit pkgs lib; };
          yaziLiveSearchCheck = import ./config/yazi/live-search.test.nix { inherit pkgs; };
          cursorAgentBridgeCheck = import ./config/opencode/plugin-tests/cursor-agent-bridge.test.nix {
            inherit pkgs;
          };
          cargoBuildEnvCheck = import ./config/opencode/plugin-tests/cargo-build-env.test.nix {
            inherit pkgs;
          };
          cursorAgentBridgeModuleTests = lib.runTests (
            import ./home/cursor-agent-bridge.test.nix { inherit lib; }
          );
          cursorAgentBridgeModuleCheck = pkgs.runCommand "cursor-agent-bridge-module-test" { } (
            if cursorAgentBridgeModuleTests == [ ] then
              ''
                echo "cursor-agent-bridge-module-test: all cases passed"
                touch "$out"
              ''
            else
              ''
                echo "cursor-agent-bridge-module-test failures:" >&2
                cat <<'EOF' >&2
                ${builtins.toJSON cursorAgentBridgeModuleTests}
                EOF
                exit 1
              ''
          );
        in
        {
          formatter = pkgs.nixfmt-rfc-style;
          packages = {
            inherit (pkgs)
              cargo-coupling
              glim
              kache
              sem
              tsql
              weave
              ;
          };
          checks =
            builtins.listToAttrs (
              map (h: {
                name = h;
                value = homeConfigurations.${h}.activationPackage;
              }) hosts
            )
            // {
              inherit (pkgs)
                cargo-coupling
                glim
                kache
                sem
                tsql
                weave
                ;
              lib-runTests = libRunTestsCheck;
              merge-dirs-test = mergeDirsCheck;
              opencode-version-alignment = opencodeVersionAlignmentCheck;
              opencode-tests = opencodeTestsCheck;
              patch-string-field-test = patchStringFieldCheck;
              configure-gpg-pinentry-test = gpgPinentryCheck;
              yazi-live-search-test = yaziLiveSearchCheck;
              cursor-agent-bridge-test = cursorAgentBridgeCheck;
              cargo-build-env-test = cargoBuildEnvCheck;
              cursor-agent-bridge-module-test = cursorAgentBridgeModuleCheck;
            };
        }
      )
    // {
      inherit homeConfigurations;
    };
}
