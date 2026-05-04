# Hyprland config: HM-managed symlink of the existing config tree.
#
# Phase 4 keeps the raw config files intact and only changes who owns
# the destination symlink. A future phase can switch to
# `wayland.windowManager.hyprland.*` native module options if/when the
# config is converted to Nix expressions.
{ pkgs, lib, ... }:

lib.mkIf pkgs.stdenv.isLinux {
  xdg.configFile."hypr".source = ../../config/hypr;
}
