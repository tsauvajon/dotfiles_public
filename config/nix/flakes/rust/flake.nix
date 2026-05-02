{
  description = "Rust development tools";

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
          nightlyRustfmt = pkgs.rust-bin.selectLatestNightlyWith (
            toolchain:
            toolchain.default.override {
              extensions = [ "rustfmt" ];
            }
          );
          packages = with pkgs; [
            cargo-llvm-cov
            sccache
            stableRust
          ];
        in
        {
          packages = {
            rust = pkgs.symlinkJoin {
              name = "dotfiles-rust";
              paths = packages;
              postBuild = ''
                rm -f "$out/bin/rustfmt" "$out/bin/cargo-fmt"
                ln -s ${nightlyRustfmt}/bin/rustfmt "$out/bin/rustfmt"
                ln -s ${nightlyRustfmt}/bin/cargo-fmt "$out/bin/cargo-fmt"
              '';
            };

            default = self.packages.${system}.rust;
          };

          devShells.default = pkgs.mkShell {
            packages = packages;
          };

          formatter = pkgs.nixfmt;
        }
      );
}
