# Rust development tools.
# Mirrors config/nix/flakes/rust/flake.nix.
{ pkgs, ... }:

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
      pkgs.sccache
      stableRust
    ];
    postBuild = ''
      rm -f "$out/bin/rustfmt" "$out/bin/cargo-fmt"
      ln -s ${nightlyRustfmt}/bin/rustfmt "$out/bin/rustfmt"
      ln -s ${nightlyRustfmt}/bin/cargo-fmt "$out/bin/cargo-fmt"
    '';
  };
in
{
  home.packages = [ rustWithNightlyFmt ];
}
