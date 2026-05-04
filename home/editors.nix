# Editors and AI coding tools.
# Mirrors config/nix/flakes/editors/flake.nix.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    obsidian
    opencode
    vim
    vscodium
  ];
}
