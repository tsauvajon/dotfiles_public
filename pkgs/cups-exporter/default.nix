# Pinned camptocamp/cups_exporter release binary.
#
# Upstream (phin1x/cups_exporter and this maintained fork) publishes no
# nixpkgs package, so pin the linux-amd64 release tarball by hash the same
# way pkgs/marksman pins its release asset. The exporter only talks to a
# CUPS server over HTTP, so the amd64 binary works on any Linux host that
# can reach localhost:631.
{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
}:

let
  version = "0.0.11";
in
# The upstream release binary is dynamically linked against glibc, so
# autoPatchelf rewrites its interpreter for the store.
stdenv.mkDerivation {
  pname = "cups-exporter";
  inherit version;

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ stdenv.cc.libc ];

  src = fetchurl {
    url = "https://github.com/camptocamp/cups_exporter/releases/download/v${version}/cups_exporter_${version}_linux_amd64.tar.gz";
    hash = "sha256-z5UkA/0Sp7Qq0p1kCS7IhDgn+RncNico3WPP+EVddcg=";
  };

  sourceRoot = ".";

  installPhase = ''
    runHook preInstall

    install -Dm755 cups_exporter "$out/bin/cups_exporter"
    install -Dm644 LICENSE "$out/share/licenses/cups-exporter/LICENSE"

    runHook postInstall
  '';

  meta = {
    description = "Prometheus exporter for CUPS print servers";
    homepage = "https://github.com/camptocamp/cups_exporter";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "cups_exporter";
  };
}
