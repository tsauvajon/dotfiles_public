# Git and forge CLIs.
# Mirrors config/nix/flakes/git/flake.nix.
# Phase 4 will replace this with `programs.git` for declarative config.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    delta
    gh
    git
    glab
  ];
}
