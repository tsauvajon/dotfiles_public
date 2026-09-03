# OpenCode shared-server Prometheus exporter.
#
# Polls the HTTP API of an `opencode serve` instance (health, projects,
# per-directory session lists) plus each provider's subscription quota
# endpoint, and exposes aggregate gauges/counters in the Prometheus text
# format. Standard library only; python3 is the sole runtime dependency.
# Runs as the opencode-exporter user service on hosts where the private
# overlay opts in (see home/personal.nix).
{
  lib,
  makeWrapper,
  python3,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "opencode-exporter";
  version = "1.2.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m0755 opencode-exporter.py $out/bin/opencode-exporter
    wrapProgram $out/bin/opencode-exporter \
      --prefix PATH : ${lib.makeBinPath [ python3 ]}
    runHook postInstall
  '';

  meta = {
    mainProgram = "opencode-exporter";
    description = "OpenCode shared-server usage prometheus exporter";
  };
}
