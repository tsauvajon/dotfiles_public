# Hyprland config: HM-managed symlink of the config tree.
{ pkgs, lib, ... }:

lib.mkIf pkgs.stdenv.isLinux {
  xdg.configFile."hypr".source = ../../config/hypr;
}
