{
  lib,
  stdenvNoCC,
  fetchurl,
  fetchFromGitHub,
  rustPlatform,
}:

let
  version = "0.11.0";

  prebuiltSources = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-FisEO7e1t+WNNEbtcHkjS9VPg50EiqSkFVVgdCaYGqs=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-GVZrpI9842wKHW9tzojlnOTyShYuGvVm9bJFc+sE6Ys=";
    };
  };

  # Keep using prebuilt assets for aarch64 and source builds for x86_64.
  sourceBuildPlatforms = [
    "x86_64-darwin"
    "x86_64-linux"
  ];

  platforms = (builtins.attrNames prebuiltSources) ++ sourceBuildPlatforms;

  source = prebuiltSources.${stdenvNoCC.hostPlatform.system} or null;

  meta = {
    description = "Zero-copy, content-addressed Rust build cache";
    homepage = "https://github.com/kunobi-ninja/kache";
    license = lib.licenses.asl20;
    mainProgram = "kache";
    inherit platforms;
  };
in
if source != null then
  stdenvNoCC.mkDerivation {
    pname = "kache";
    inherit version;

    src = fetchurl {
      url = "https://github.com/kunobi-ninja/kache/releases/download/v${version}/kache-${source.target}.tar.gz";
      inherit (source) hash;
    };

    sourceRoot = ".";

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin"
      install -m755 kache "$out/bin/kache"

      runHook postInstall
    '';

    # Kache's prebuilt Linux asset is a musl binary, so it can execute inside the
    # Nix build sandbox. GNU Linux release assets would need the FHS loader path.
    doInstallCheck = stdenvNoCC.hostPlatform.isDarwin || lib.hasInfix "musl" source.target;
    installCheckPhase = ''
      runHook preInstallCheck

      "$out/bin/kache" --version || "$out/bin/kache" --help

      runHook postInstallCheck
    '';

    inherit meta;
  }
else if builtins.elem stdenvNoCC.hostPlatform.system sourceBuildPlatforms then
  rustPlatform.buildRustPackage {
    pname = "kache";
    inherit version;

    src = fetchFromGitHub {
      owner = "kunobi-ninja";
      repo = "kache";
      rev = "v${version}";
      hash = "sha256-AJjfnIDspLz9Fjn1cVVx65SB3b4Eh8uaWp8XnskuhhA=";
    };

    cargoHash = "sha256-iUW19GqD0Gspn6F5uGMQiYSnGkBf2Isq5cw2Ef7sXDo=";
    cargoBuildFlags = [
      "-p"
      "kache"
    ];
    doCheck = false;

    env.RUSTC_WRAPPER = "";

    inherit meta;
  }
else
  throw "kache is not packaged for ${stdenvNoCC.hostPlatform.system}"
