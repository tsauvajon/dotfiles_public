# mako notification daemon config: HM-managed symlink.
{ pkgs, lib, ... }:

lib.mkIf pkgs.stdenv.isLinux {
  xdg.configFile."mako".source = ../../config/mako;
}
