# Filesystem navigation and search tools.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    bat
    dumap
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
    qrtool
    ripgrep
    tabiew
    tdf
    xz
    yq
    yazi
    zoxide
  ];
}
