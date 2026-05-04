# rofi launcher config: HM-managed symlink.
{ pkgs, lib, ... }:

lib.mkIf pkgs.stdenv.isLinux {
  xdg.configFile."rofi".source = ../../config/rofi;
}
