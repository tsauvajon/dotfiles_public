# nixGL wrapper helper.
#
# On Linux, wraps a graphical package's binary so it launches via nixGL,
# which is needed for OpenGL/Vulkan to find the host driver. On macOS
# (and any non-Linux system) this is a no-op and returns the package
# untouched.
#
# Usage:
#   wrapWithNixGL alacritty "alacritty"
{
  pkgs,
  nixgl,
  nixgl-nixpkgs,
  nvidiaVersion ? null,
}:

let
  inherit (pkgs.stdenv.hostPlatform) system;
  nvidiaVersionFromEnv = builtins.getEnv "NIXGL_NVIDIA_VERSION";
  resolvedNvidiaVersion = if nvidiaVersion == null then nvidiaVersionFromEnv else nvidiaVersion;
  nixglPkgs = import nixgl {
    pkgs = import nixgl-nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    nvidiaVersion = if resolvedNvidiaVersion == "" then null else resolvedNvidiaVersion;
    enable32bits = system == "x86_64-linux";
    enableIntelX86Extensions = system == "x86_64-linux";
  };
  nixglLauncher = "${nixglPkgs.auto.nixGLDefault}/bin/nixGL";
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
