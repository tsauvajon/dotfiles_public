# Desktop session tools (Linux-only). On non-Linux this module
# contributes nothing.
{ pkgs, lib, ... }:

lib.mkIf pkgs.stdenv.isLinux {
  # `keepassxc` is declared cross-platform in `home/apps.nix`; do not
  # add it back here.
  home.packages = with pkgs; [
    audacity
    bibata-cursors
    dart-sass
    # ddcutil — DDC/CI monitor control. Used by the `monitor-input`
    # wrapper (see home/programs/monitor-input.nix). Requires the
    # i2c-dev kernel module and the user in the `i2c` group; that
    # layer is system-level and not managed by Home Manager.
    ddcutil
    # firefox
    hyprpicker
    nerd-fonts.jetbrains-mono
    libnotify
    mako
    papirus-icon-theme
    rofi
    swappy
    waybar
  ];
}
