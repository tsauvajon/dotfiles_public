{ lib }:

let
  rustToolchain = import ./rust-toolchain.nix;
  fakePkgs = {
    rust-bin.nightly."2026-08-17".default.override = args: {
      inherit (args) extensions;
      outPath = "/nightly";
    };
    symlinkJoin = args: args;
    writeShellScriptBin = name: text: {
      inherit name text;
      outPath = "/cargo-wrapper";
    };
  };
  toolchain = rustToolchain { pkgs = fakePkgs; };
  cargoWrapper = builtins.elemAt toolchain.paths 1;
  craneliftDefault = builtins.concatStringsSep "" [
    "CARGO_PROFILE_DEV_CODEGEN_BACKEND=\""
    "\${CARGO_PROFILE_DEV_CODEGEN_BACKEND:-cranelift}\""
  ];
  unstableDefault = builtins.concatStringsSep "" [
    "CARGO_UNSTABLE_CODEGEN_BACKEND=\""
    "\${CARGO_UNSTABLE_CODEGEN_BACKEND:-true}\""
  ];
in
{
  testRustToolchainExtensions = {
    expr = (builtins.head toolchain.paths).extensions;
    expected = [
      "clippy"
      "llvm-tools-preview"
      "rust-analyzer"
      "rust-src"
      "rustfmt"
      "rustc-codegen-cranelift-preview"
    ];
  };

  testRustToolchainName = {
    expr = toolchain.name;
    expected = "rust-nightly-2026-08-17-cranelift";
  };

  testCargoWrapperDefaultsCranelift = {
    expr = lib.hasInfix craneliftDefault cargoWrapper.text;
    expected = true;
  };

  testCargoWrapperPreservesBackendOverride = {
    expr =
      lib.hasInfix craneliftDefault cargoWrapper.text && lib.hasInfix unstableDefault cargoWrapper.text;
    expected = true;
  };

  testCargoWrapperUsesPinnedToolchainAndForwardsArguments = {
    expr =
      lib.hasInfix "export RUSTC=\"/nightly/bin/rustc\"" cargoWrapper.text
      && lib.hasInfix "exec \"/nightly/bin/cargo\" \"$@\"" cargoWrapper.text;
    expected = true;
  };

  testCargoWrapperReplacesRawCargo = {
    expr = lib.hasInfix "ln -s /cargo-wrapper/bin/cargo \"$out/bin/cargo\"" toolchain.postBuild;
    expected = true;
  };
}
