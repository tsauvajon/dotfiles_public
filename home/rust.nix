# Rust development tools.
{ pkgs, lib, ... }:

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
  # `cargo-nextest` ships separately so a private overlay can shadow
  # it (e.g. a private overlay may expose a vendored nextest with the same
  # binary name). `lib.lowPrio` makes the public copy lose the
  # buildEnv collision; without a competing definition it is used as
  # the only `cargo-nextest` on PATH.
  home.packages = [
    pkgs.cargo-coupling
    pkgs.protobuf
    rustWithNightlyFmt
    (lib.lowPrio pkgs.cargo-nextest)
  ];
}
