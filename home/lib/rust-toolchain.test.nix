{ lib }:

let
  rustToolchain = import ./rust-toolchain.nix;
  fakePkgs.rust-bin.stable.latest.default.override = args: args;
in
{
  testRustToolchainExtensions = {
    expr = (rustToolchain { pkgs = fakePkgs; }).extensions;
    expected = [
      "clippy"
      "llvm-tools-preview"
      "rust-analyzer"
      "rust-src"
    ];
  };
}
