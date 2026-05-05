# Shell and terminal workflow tools.
# Mirrors config/nix/flakes/shell/flake.nix, including nixGL wrapping for
# graphical terminals on Linux.
{
  pkgs,
  lib,
  inputs,
  nixglNvidiaVersion ? null,
  ...
}:

let
  wrapWithNixGL = import ./lib/wrap-with-nixgl.nix {
    inherit pkgs;
    inherit (inputs) nixgl nixgl-nixpkgs;
    nvidiaVersion = nixglNvidiaVersion;
  };
in
{
  # tmux is provided by programs.tmux in home/programs/tmux.nix.
  home.packages = [
    (wrapWithNixGL pkgs.alacritty "alacritty")
    (pkgs.direnv.overrideAttrs { doCheck = false; })
    pkgs.fish
    pkgs.just
    (wrapWithNixGL pkgs.kitty "kitty")
    pkgs.nix-direnv
    pkgs.zellij
    pkgs.zsh
    pkgs.zsh-autosuggestions
    pkgs.zsh-completions
  ];
}
