# Shell and terminal workflow tools.
# Mirrors config/nix/flakes/shell/flake.nix, including nixGL wrapping for
# graphical terminals on Linux.
{
  pkgs,
  lib,
  inputs,
  nixglNvidiaVersion ? null,
  nixglNvidiaHash ? null,
  ...
}:

let
  wrapWithNixGL = import ./lib/wrap-with-nixgl.nix {
    inherit pkgs;
    inherit (inputs) nixgl nixgl-nixpkgs;
    nvidiaVersion = nixglNvidiaVersion;
    nvidiaHash = nixglNvidiaHash;
  };
in
{
  # tmux is provided by programs.tmux in home/programs/tmux.nix.
  home.packages = [
    (wrapWithNixGL pkgs.alacritty "alacritty")
    pkgs.bash
    pkgs.cmake
    pkgs.coreutils
    pkgs.curl
    pkgs.fish
    pkgs.just
    (wrapWithNixGL pkgs.kitty "kitty")
    pkgs.socat
    pkgs.websocat
    pkgs.zellij
    pkgs.zsh
    pkgs.zsh-autosuggestions
    pkgs.zsh-completions
    pkgs.zsh-powerlevel10k
    pkgs.zsh-syntax-highlighting
  ];
}
