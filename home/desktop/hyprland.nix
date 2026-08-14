# Hyprland 0.55+ Lua configuration with the selected terminal's rules.
{
  pkgs,
  lib,
  terminal,
  ...
}:

let
  hyprConfig = pkgs.runCommand "hypr-config" { } ''
    mkdir -p "$out"
    cp -R --no-preserve=mode ${../../config/hypr}/. "$out"
    substituteInPlace "$out/hyprland.lua" \
      --replace-fail '@defaultTerminalClass@' '${terminal.hyprlandClass}'
  '';
in
lib.mkIf pkgs.stdenv.isLinux {
  xdg.configFile."hypr".source = hyprConfig;
}
