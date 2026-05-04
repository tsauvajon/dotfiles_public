# Desktop session tools (Linux-only).
# Mirrors config/nix/flakes/desktop/flake.nix; on non-Linux this module
# contributes nothing.
{ pkgs, lib, ... }:

lib.mkIf pkgs.stdenv.isLinux {
  home.packages = with pkgs; [
    audacity
    bibata-cursors
    dart-sass
    # firefox
    hyprpicker
    nerd-fonts.jetbrains-mono
    keepassxc
    libnotify
    mako
    swappy
    waybar
  ];
}
