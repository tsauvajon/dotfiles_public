# ddcctl: macOS DDC/CI monitor control for Intel Macs.
#
# Apple Silicon Macs use `m1ddc` from nixpkgs instead — `ddcctl` does not
# work on aarch64-darwin because the IOFramebuffer DDC path it relies on
# was removed in that architecture.
#
# Source pinned via the `ddcctl-src` flake input (kfix/ddcctl is in
# upstream-declared maintenance mode, so we want a fixed commit).
{
  stdenv,
  lib,
  src,
}:

stdenv.mkDerivation {
  pname = "ddcctl";
  # The upstream Makefile has no version string and the repo's tags are
  # stale; track the pinned commit short hash for traceability.
  version = "unstable-2024-06c7ab6";

  inherit src;

  enableParallelBuilding = true;

  # The Makefile builds bin/release/ddcctl by default; its `install`
  # target writes to /usr/local/bin which we override with our own
  # install phase.
  installPhase = ''
    runHook preInstall
    install -Dm755 bin/release/ddcctl "$out/bin/ddcctl"
    runHook postInstall
  '';

  meta = {
    description = "Control external Mac monitors via DDC/CI";
    homepage = "https://github.com/kfix/ddcctl";
    license = lib.licenses.gpl3Only;
    # Apple Silicon support is unreliable; gate to Intel Darwin to avoid
    # surprising aarch64 evaluations.
    platforms = [ "x86_64-darwin" ];
    mainProgram = "ddcctl";
  };
}
