# Filesystem navigation and search tools.
# Mirrors config/nix/flakes/fs/flake.nix.
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
