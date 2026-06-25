{
  fetchurl,
  lib,
  stdenvNoCC,
}:

let
  version = "0.7.0";
  sources = {
    aarch64-darwin = {
      asset = "herdr-macos-aarch64";
      hash = "sha256-CUbBxd45bRQEkGyByEoM70evXhXJqsPAWMOTa4M/4xE=";
    };
    x86_64-darwin = {
      asset = "herdr-macos-x86_64";
      hash = "sha256-bGHNtnx5uNBibhCbnY2GNcZqgL/tIayf5u/fHdjSfA8=";
    };
    x86_64-linux = {
      asset = "herdr-linux-x86_64";
      hash = "sha256-rSpdSApOBGCandMKGewHhUV432tfDqkpkkaWO69ANjs=";
    };
  };

  source =
    sources.${stdenvNoCC.hostPlatform.system}
      or (throw "herdr is not packaged for ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "herdr";
  inherit version;

  src = fetchurl {
    url = "https://github.com/ogulcancelik/herdr/releases/download/v${version}/${source.asset}";
    inherit (source) hash;
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 "$src" "$out/bin/herdr"

    runHook postInstall
  '';

  # Linux release assets are dynamically-linked GNU binaries. They need the FHS
  # loader path (/lib64/ld-linux-*) that is absent in the Nix build sandbox.
  doInstallCheck = stdenvNoCC.hostPlatform.isDarwin;
  installCheckPhase = ''
    runHook preInstallCheck

    "$out/bin/herdr" --version || "$out/bin/herdr" --help

    runHook postInstallCheck
  '';

  meta = {
    description = "Terminal workspace manager for AI coding agents";
    homepage = "https://github.com/ogulcancelik/herdr";
    license = lib.licenses.agpl3Plus;
    mainProgram = "herdr";
    platforms = builtins.attrNames sources;
  };
}
