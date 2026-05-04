# Top-level Home Manager module for Thomas's dotfiles.
#
# Imports each per-domain module. Per-platform gating is done inside
# each module via `lib.mkIf pkgs.stdenv.isLinux` (and similar) so that
# both `homeConfigurations.thomas-darwin` and `thomas-linux` can import
# the same set of files.
#
# Phase 1: only `home.packages` is set across modules; existing dotfile
# symlinks, merges, and template generation remain managed by the Rust
# setup tool. Later phases progressively migrate those into HM modules.
{ ... }:

{
  imports = [
    ./rust.nix
    ./git.nix
    ./fs.nix
    ./shell.nix
    ./editors.nix
    ./desktop.nix
    ./helix-langs.nix
    ./helix-plugins.nix
    ./opencode.nix
  ];
}
