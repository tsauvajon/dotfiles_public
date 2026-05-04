# waybar config + compiled style.css.
#
# The Rust tool's src/waybar.rs used `grass` to compile
# config/waybar/styles/index.scss into ~/.local/share/dotfiles/waybar/style.css.
# Phase 4 ports that to a `pkgs.runCommand` derivation that uses
# dart-sass at evaluation time. The non-stylesheet entries (config.jsonc,
# scripts, icons) are HM-managed symlinks straight from config/waybar/.
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
