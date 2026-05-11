# Filesystem navigation and search tools.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    bat
    doxx
    dust
    eza
    fastfetch
    fd
    fzf
    htop
    imagemagick
    jiq
    jq
    ouch
    qpdf
    ripgrep
    tabiew
    tdf
    xz
    yq
    yazi
    zoxide
  ];
}
