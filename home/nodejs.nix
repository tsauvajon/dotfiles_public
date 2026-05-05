# JavaScript tooling.
# Bun is the global runtime/package manager. Project-specific Node versions
# should use a local flake or `nix shell` when needed.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    bun
  ];
}
