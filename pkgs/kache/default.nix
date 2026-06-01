{
  lib,
  stdenv,
  fetchurl,
  fetchFromGitHub,
  rustPlatform,
}:

let
  version = "0.4.0";

  prebuiltSources = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-qiJ4OBqlnoUpoksGXHY5WbIlQh3AyhlgPr5AOmP+Rqk=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-5W7O2iTTiT8fImAa+IjRxlr5tG9TnluhYnyTN4JFYtA=";
    };
  };

  sourceBuildPlatforms = [
    "x86_64-darwin"
    "x86_64-linux"
  ];

  platforms = (builtins.attrNames prebuiltSources) ++ sourceBuildPlatforms;

  source = prebuiltSources.${stdenv.hostPlatform.system} or null;

  meta = {
    description = "Zero-copy, content-addressed Rust build cache";
    homepage = "https://github.com/kunobi-ninja/kache";
    license = lib.licenses.asl20;
    mainProgram = "kache";
    inherit platforms;
  };
in
if source != null then
  stdenv.mkDerivation {
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

    inherit meta;
  }
else if builtins.elem stdenv.hostPlatform.system sourceBuildPlatforms then
  rustPlatform.buildRustPackage {
    pname = "kache";
    inherit version;

    src = fetchFromGitHub {
      owner = "kunobi-ninja";
      repo = "kache";
      rev = "v${version}";
      hash = "sha256-vtU+WgMsXzE+NC8/X7UlkHaJkClL/hlVkxgv4uU8z7E=";
    };

    cargoHash = "sha256-yc7E1fDPe3FVflKvkR8faQGFfN+W2YQAXZKrxO5kaq0=";
    cargoBuildFlags = [
      "-p"
      "kache"
    ];
    doCheck = false;

    env.RUSTC_WRAPPER = "";

    inherit meta;
  }
else
  throw "kache is not packaged for ${stdenv.hostPlatform.system}"
