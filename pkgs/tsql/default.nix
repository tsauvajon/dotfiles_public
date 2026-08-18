{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  sources = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-DumyrDn8KMisE9/kGc5Lh2raEc8mkd1QViSwj5Iy3Cg=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      hash = "sha256-WABZC+8a7k01/HB50PizJZ7fHefVJa7uSdp49UFKYbQ=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-gnu";
      hash = "sha256-iqlpkgq43mob4v9SOX8ZUSD2xMOjbwWqDF3GMsqzLN8=";
    };
  };

  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "tsql is not packaged for ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation rec {
  pname = "tsql";
  version = "0.7.0";

  src = fetchurl {
    url = "https://github.com/fcoury/tsql/releases/download/v${version}/tsql-${source.target}.tar.gz";
    inherit (source) hash;
  };

  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin"
    install -m755 tsql "$out/bin/tsql"

    runHook postInstall
  '';

  # Linux release assets are dynamically-linked GNU binaries. They need the FHS
  # loader path (/lib64/ld-linux-*) that is absent in the Nix build sandbox.
  doInstallCheck = stdenvNoCC.hostPlatform.isDarwin;
  installCheckPhase = ''
    runHook preInstallCheck

    "$out/bin/tsql" --version || "$out/bin/tsql" --help

    runHook postInstallCheck
  '';

  meta = {
    description = "Modern, keyboard-first PostgreSQL CLI";
    homepage = "https://github.com/fcoury/tsql";
    license = lib.licenses.mit;
    mainProgram = "tsql";
    platforms = builtins.attrNames sources;
  };
}
