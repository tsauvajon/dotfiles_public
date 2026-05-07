# Desktop session tools (Linux-only).
# Mirrors config/nix/flakes/desktop/flake.nix; on non-Linux this module
# contributes nothing.
{ pkgs, lib, ... }:

lib.mkIf pkgs.stdenv.isLinux {
  # `keepassxc` is declared cross-platform in `home/apps.nix`; do not
  # add it back here.
  home.packages = with pkgs; [
    audacity
    bibata-cursors
    dart-sass
    # firefox
    hyprpicker
    nerd-fonts.jetbrains-mono
    libnotify
    mako
    swappy
    waybar
  ];
}
