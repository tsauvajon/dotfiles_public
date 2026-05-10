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
    jiq
    jq
    ouch
    ripgrep
    tabiew
    tdf
    xz
    yq
    yazi
    zoxide
  ];
}
