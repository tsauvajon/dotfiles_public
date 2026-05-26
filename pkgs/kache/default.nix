{
  lib,
  stdenv,
  fetchurl,
}:

let
  sources = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-g3UFzJ6FEwFbp58YmxVL3D5DRgA06hrgFyJ5CHF3rNc=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      hash = "sha256-GPcxZYlXEeF8NSNPOPasLk15K9aUPD+fJrSGm7NqfVE=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-l6+LbxzaXqmBBYkmKB2belmy9kqs2GcX9GGD3HzLimA=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-PKOctuBD0afkq1T3V1YDTAyUq3A5Qpm3Xx6Emlq3wYQ=";
    };
  };

  source =
    sources.${stdenv.hostPlatform.system}
      or (throw "kache is not packaged for ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation rec {
  pname = "kache";
  version = "0.3.1";

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

  meta = {
    description = "Zero-copy, content-addressed Rust build cache";
    homepage = "https://github.com/kunobi-ninja/kache";
    license = lib.licenses.asl20;
    mainProgram = "kache";
    platforms = builtins.attrNames sources;
  };
}
