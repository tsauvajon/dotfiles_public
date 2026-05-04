# waybar config + compiled style.css.
#
# Compiles config/waybar/styles/index.scss to a CSS string at build
# time via dart-sass. Other entries (config.jsonc, scripts, icons,
# catppuccin theme) are HM-managed symlinks straight from
# config/waybar/.
{
  pkgs,
  lib,
  ...
}:

let
  waybarSrc = ../../config/waybar;
  styleCss = pkgs.runCommand "waybar-style.css" { } ''
    ${pkgs.dart-sass}/bin/sass --style=expanded ${waybarSrc}/styles/index.scss > "$out"
  '';
in
lib.mkIf pkgs.stdenv.isLinux {
  # Symlink each entry under config/waybar/ except style.css (compiled
  # below) and styles/ (source-only, not used at runtime).
  xdg.configFile = {
    "waybar/config.jsonc".source = "${waybarSrc}/config.jsonc";
    "waybar/scripts".source = "${waybarSrc}/scripts";
    "waybar/icons".source = "${waybarSrc}/icons";
    "waybar/catppuccin".source = "${waybarSrc}/catppuccin";
    "waybar/style.css".source = styleCss;
  };
}
