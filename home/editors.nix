# Editors and AI coding tools.
# Mirrors config/nix/flakes/editors/flake.nix.
{ pkgs, lib, ... }:

{
  home.packages =
    with pkgs;
    [
      obsidian
      vim
      vscodium
    ]
    ++ lib.optional (stdenv.hostPlatform.system != "x86_64-darwin") opencode;
}
