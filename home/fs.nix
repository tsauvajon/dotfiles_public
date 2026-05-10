# Filesystem navigation and search tools.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    bat
    dust
    eza
    fastfetch
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
