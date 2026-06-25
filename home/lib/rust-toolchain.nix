{ pkgs }:

pkgs.rust-bin.stable.latest.default.override {
  extensions = [
    "clippy"
    "llvm-tools-preview"
    "rust-analyzer"
    "rust-src"
  ];
}
