# Shell and terminal workflow tools.
# Mirrors config/nix/flakes/shell/flake.nix, including nixGL wrapping for
# graphical terminals on Linux.
{ pkgs, lib, inputs, ... }:

let
  wrapWithNixGL = import ./lib/wrap-with-nixgl.nix {
    inherit pkgs;
    inherit (inputs) nixgl nixgl-nixpkgs;
  };
in
{
  home.packages = [
    (wrapWithNixGL pkgs.alacritty "alacritty")
    pkgs.asdf-vm
    (pkgs.direnv.overrideAttrs { doCheck = false; })
    pkgs.fish
    pkgs.jq
    pkgs.just
    (wrapWithNixGL pkgs.kitty "kitty")
    pkgs.nix-direnv
    pkgs.tmux
    pkgs.zellij
    pkgs.zsh
    pkgs.zsh-autosuggestions
    pkgs.zsh-completions
  ];
}
