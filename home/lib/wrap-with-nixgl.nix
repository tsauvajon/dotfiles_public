# nixGL wrapper helper.
#
# On Linux, wraps a graphical package's binary so it launches via nixGL,
# which is needed for OpenGL/Vulkan to find the host driver. On macOS
# (and any non-Linux system) this is a no-op and returns the package
# untouched.
#
# Usage:
#   wrapWithNixGL alacritty "alacritty"
#
# Pure evaluation: pass `nvidiaVersion` AND `nvidiaHash` together (the
# sha256 of the matching `NVIDIA-Linux-x86_64-<version>.run` from
# https://download.nvidia.com/XFree86/). Without a hash, nixGL falls
# back to `builtins.fetchurl` and the activation package only evaluates
# under `--impure`.
{
  pkgs,
  nixgl,
  nixgl-nixpkgs,
  nvidiaVersion ? null,
  nvidiaHash ? null,
}:

let
  inherit (pkgs.stdenv.hostPlatform) system;
  nixglPkgs = import nixgl {
    pkgs = import nixgl-nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    inherit nvidiaVersion nvidiaHash;
    enable32bits = system == "x86_64-linux";
    enableIntelX86Extensions = system == "x86_64-linux";
  };
  # Build the launcher explicitly instead of using `nixglPkgs.auto.nixGLDefault`.
  # `auto.nixGLDefault` reconstructs the nvidia derivation via
  # `nvidiaPackages { version = ...; }` without forwarding the sha256, which
  # forces an impure `builtins.fetchurl` for the driver. Using `nixGLNvidia`
  # from the top-level scope picks up the sha256 we passed above.
  nixGL =
    if nvidiaVersion != null then
      nixglPkgs.nixGLCommon nixglPkgs.nixGLNvidia
    else
      nixglPkgs.nixGLCommon nixglPkgs.nixGLIntel;
  nixglLauncher = "${nixGL}/bin/nixGL";
in
package: binary:
if pkgs.stdenv.isLinux then
  pkgs.symlinkJoin {
    name = "${package.pname or binary}-nixgl";
    paths = [ package ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm "$out/bin/${binary}"
      makeWrapper ${pkgs.writeShellScript "${binary}-nixgl-launcher" ''
        exec ${nixglLauncher} ${package}/bin/${binary} "$@"
      ''} "$out/bin/${binary}"
    '';
  }
else
  package
