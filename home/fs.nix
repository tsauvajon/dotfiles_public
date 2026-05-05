# Filesystem navigation and search tools.
# Mirrors config/nix/flakes/fs/flake.nix.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    bat
    eza
    fd
    fzf
    jq
    ripgrep
    tabiew
    xz
    yq
    yazi
    zoxide
  ];
}
