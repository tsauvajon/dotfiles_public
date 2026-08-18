{ pkgs }:

let
  nightly = pkgs.rust-bin.nightly."2026-08-17".default.override {
    extensions = [
      "clippy"
      "llvm-tools-preview"
      "rust-analyzer"
      "rust-src"
      "rustfmt"
      "rustc-codegen-cranelift-preview"
    ];
  };
  cargoWrapper = pkgs.writeShellScriptBin "cargo" ''
    export RUSTC="${nightly}/bin/rustc"
    export CARGO_UNSTABLE_CODEGEN_BACKEND="''${CARGO_UNSTABLE_CODEGEN_BACKEND:-true}"
    export CARGO_PROFILE_DEV_CODEGEN_BACKEND="''${CARGO_PROFILE_DEV_CODEGEN_BACKEND:-cranelift}"

    exec "${nightly}/bin/cargo" "$@"
  '';
in
pkgs.symlinkJoin {
  name = "rust-nightly-2026-08-17-cranelift";
  paths = [
    nightly
    cargoWrapper
  ];
  postBuild = ''
    rm -f "$out/bin/cargo"
    ln -s ${cargoWrapper}/bin/cargo "$out/bin/cargo"
  '';
}
