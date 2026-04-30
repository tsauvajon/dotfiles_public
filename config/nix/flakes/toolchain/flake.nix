{
  description = "Personal dev toolchain for OpenCode + worktrees";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      rust-overlay,
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
            extensions = [
              "clippy"
              "llvm-tools-preview"
              "rust-analyzer"
              "rust-src"
            ];
          };
          nightlyRustfmtToolchain = pkgs.rust-bin.selectLatestNightlyWith (
            toolchain:
            toolchain.default.override {
              extensions = [ "rustfmt" ];
            }
          );
          basePackages =
            with pkgs;
            [
              asdf-vm
              cargo-llvm-cov
              delta
              (direnv.overrideAttrs { doCheck = false; })
              fd
              fish
              fzf
              gh
              git
              jq
              just
              nix-direnv
              stableRust
              opencode
              ripgrep
              sccache
              tmux
              vim
              vscodium
              zoxide
            ]
            ++ (if pkgs.stdenv.isLinux then [ pkgs.mako ] else [ ]);
        in
        {
          packages = {
            toolchain = pkgs.symlinkJoin {
              name = "dotfiles-toolchain";
              paths = basePackages;
              postBuild = ''
                rm -f "$out/bin/rustfmt" "$out/bin/cargo-fmt"
                ln -s ${nightlyRustfmtToolchain}/bin/rustfmt "$out/bin/rustfmt"
                ln -s ${nightlyRustfmtToolchain}/bin/cargo-fmt "$out/bin/cargo-fmt"
              '';
            };

            default = self.packages.${system}.toolchain;
          };

          devShells.default = pkgs.mkShell {
            packages = basePackages;

            shellHook = ''
              export DEV_ROOT="''${DEV_ROOT:-$HOME/dev}"
              export PATH="$HOME/.asdf/shims:$PATH"
              echo "Dotfiles dev shell ready. Run: task bootstrap"
            '';
          };

          formatter = pkgs.nixfmt;
        }
      );
}
