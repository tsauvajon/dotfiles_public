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
    ./bootstrap.nix
    ./desktop
    ./editors.nix
    ./files.nix
    ./fs.nix
    ./helix-langs.nix
    ./helix-plugins.nix
    ./launchd.nix
    ./nodejs.nix
    ./opencode.nix
    ./sessionEnv.nix
    ./programs/aerospace.nix
    ./programs/alacritty.nix
    ./programs/aliases.nix
    ./programs/cargo.nix
    ./programs/cross-shell-aliases.nix
    ./programs/cross-shell-functions.nix
    ./programs/functions.nix
    ./programs/git.nix
    ./programs/goto.nix
    ./programs/scripts.nix
    ./programs/task.nix
    ./programs/tmux.nix
    ./rust.nix
    ./shell.nix
  ];
}
