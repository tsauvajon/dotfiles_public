# Filesystem navigation and search tools.
# Mirrors config/nix/flakes/fs/flake.nix.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    bat
    eza
    fd
    fzf
    ripgrep
    xz
    yq
    yazi
    zoxide
  ];
}
