{
  lib,
  stdenvNoCC,
  fortune,
}:

stdenvNoCC.mkDerivation {
  pname = "tool-habit";
  version = "1.0.0";

  src = ../../config/fortune-habits/tool-habits;

  dontUnpack = true;
  dontConfigure = true;

  nativeBuildInputs = [ fortune ];

  buildPhase = ''
    runHook preBuild

    strfile "$src" tool-habits.dat

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/share/fortune-habits"
    install -m 444 "$src" "$out/share/fortune-habits/tool-habits"
    install -m 444 tool-habits.dat "$out/share/fortune-habits/tool-habits.dat"

    install -m 755 ${./tool-habit.sh} "$out/bin/tool-habit"
    substituteInPlace "$out/bin/tool-habit" \
      --replace-fail @fortune@ ${fortune}/bin/fortune \
      --replace-fail @habits@ "$out/share/fortune-habits/tool-habits"
    patchShebangs "$out/bin/tool-habit"
    chmod 755 "$out/bin/tool-habit"

    runHook postInstall
  '';

  meta = {
    description = "Print a random habit reminder for installed CLI tools";
    license = lib.licenses.mit;
    mainProgram = "tool-habit";
    platforms = lib.platforms.unix;
  };
}
