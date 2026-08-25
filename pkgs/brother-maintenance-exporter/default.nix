# Brother printer maintenance-info Prometheus exporter.
#
# Decodes the private brInfoMaintenance octet string (toner/drum percentages,
# hidden from the standard Printer-MIB on third-party cartridges), the paper
# tray table, and the active LCD alert line into Prometheus gauges. The script
# is the canonical copy of homeserver's infra/arch-printer-exporter/
# brother-maintenance-exporter.py; update both together.
{
  lib,
  makeWrapper,
  net-snmp,
  python3,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "brother-maintenance-exporter";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    install -m0755 brother-maintenance-exporter.py $out/bin/brother-maintenance-exporter
    wrapProgram $out/bin/brother-maintenance-exporter \
      --prefix PATH : ${lib.makeBinPath [ python3 net-snmp ]}
    runHook postInstall
  '';

  meta = {
    mainProgram = "brother-maintenance-exporter";
    description = "Brother printer maintenance-info (toner/drum/tray) prometheus exporter";
  };
}
