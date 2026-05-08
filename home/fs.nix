# Filesystem navigation and search tools.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    bat
    dust
    eza
    fd
    fzf
    htop
    jq
    ripgrep
    tabiew
    xz
    yq
    yazi
    zoxide
  ];
}
