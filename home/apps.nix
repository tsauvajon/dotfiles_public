# Cross-platform user-facing applications.
#
# Tools that work the same way on Linux and Darwin live here. Use
# `home/desktop/packages.nix` for Linux-only desktop bits and
# `home/darwin-apps.nix` for Darwin-only HM-level packages.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    keepassxc
  ];
}
