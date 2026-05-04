# Linux-only desktop session: packages plus per-tool config modules.
# Each module is internally gated with `lib.mkIf pkgs.stdenv.isLinux`,
# so importing this directory on macOS is a no-op.
{ ... }:

{
  imports = [
    ./packages.nix
    ./hyprland.nix
    ./mako.nix
    ./waybar.nix
    ./rofi.nix
  ];
}
