# Desktop session tools (Linux-only). On non-Linux this module
# contributes nothing.
{
  pkgs,
  lib,
  inputs,
  ...
}:

lib.mkIf pkgs.stdenv.isLinux {
  # `keepassxc` is declared cross-platform in `home/apps.nix`; do not
  # add it back here.
  home.packages = with pkgs; [
    alsa-utils
    audacity
    bibata-cursors
    brightnessctl
    dart-sass
    # ddcutil — DDC/CI monitor control. Used by the `monitor-input`
    # wrapper (see home/programs/monitor-input.nix). Requires the
    # i2c-dev kernel module and the user in the `i2c` group; that
    # layer is system-level and not managed by Home Manager.
    ddcutil
    ffmpegthumbnailer
    # firefox
    grim
    # grimblast is provided by nixpkgs for Waybar's area/output capture scripts.
    grimblast
    gvfs
    hyprlock
    hyprpicker
    nerd-fonts.jetbrains-mono
    libnotify
    mako
    nautilus
    papirus-icon-theme
    playerctl
    rofi
    slurp
    sushi
    swappy
    udiskie
    waybar
    wl-clipboard
    inputs.ai-usagebar.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
