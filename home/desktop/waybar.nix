# waybar config + compiled style.css.
#
# Compiles config/waybar/styles/index.scss to a CSS string at build
# time via dart-sass. The generated CSS contains a runtime
# `@import "catppuccin/themes/mocha.css"` (CSS imports stay literal in
# dart-sass output), so waybar resolves the path relative to
# ~/.config/waybar/ at startup.
#
# `inputs.catppuccin` (catppuccin/nix metaflake) ships catppuccin-waybar
# with the per-flavor CSS files at the top of the package output. We
# mount it at `catppuccin/themes/` so `mocha.css`, `frappe.css`, etc.
# land at the path the SCSS import expects.
{
  pkgs,
  lib,
  inputs,
  ...
}:

let
  waybarSrc = ../../config/waybar;
  catppuccinWaybar = inputs.catppuccin.packages.${pkgs.stdenv.hostPlatform.system}.waybar;

  styleCss = pkgs.runCommand "waybar-style.css" { } ''
    ${pkgs.dart-sass}/bin/sass --style=expanded ${waybarSrc}/styles/index.scss > "$out"
  '';
in
lib.mkIf pkgs.stdenv.isLinux {
  xdg.configFile = {
    "waybar/config.jsonc".source = "${waybarSrc}/config.jsonc";
    "waybar/scripts".source = "${waybarSrc}/scripts";
    "waybar/icons".source = "${waybarSrc}/icons";
    "waybar/catppuccin/themes".source = catppuccinWaybar;
    "waybar/style.css".source = styleCss;
  };
}
