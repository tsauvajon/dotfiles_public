{
  fetchurl,
  lib,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "marksman";
  version = "2026-02-08";

  src = fetchurl {
    url = "https://github.com/artempyanykh/marksman/releases/download/2026-02-08/marksman-macos";
    hash = "sha256-aoAcF7WsDbppeHxSgrOzvUFuZsliU/rgmNMRxrvRgzs=";
  };

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 "$src" "$out/bin/marksman"

    runHook postInstall
  '';

  meta = {
    description = "Markdown language server";
    homepage = "https://github.com/artempyanykh/marksman";
    license = lib.licenses.mit;
    mainProgram = "marksman";
    platforms = lib.platforms.darwin;
  };
}
