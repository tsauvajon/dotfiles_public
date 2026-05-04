#!/usr/bin/env bash
# Bootstrap the dotfiles by running Home Manager.
#
# Phase 7 retired the Rust setup tool. This shim:
#   1. Verifies Nix is installed.
#   2. Resolves the host attribute (defaults: macOS -> thomas-darwin,
#      Linux -> thomas-linux; override with $DOTFILES_HOST).
#   3. Activates the HM generation defined in home/. The HM
#      activation block in home/bootstrap.nix records the dotfiles
#      path, cleans up legacy Rust-managed symlinks, and runs
#      `task bootstrap`.
#
# The legacy `--check` flag has been retired. Use:
#   nix build --impure --dry-run \
#     "path:.#homeConfigurations.<host>.activationPackage"
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export DOTFILES

if ! command -v nix >/dev/null 2>&1; then
  printf 'error: nix not found on PATH. Install Nix from https://nixos.org first.\n' >&2
  exit 1
fi

case "${DOTFILES_HOST:-}" in
  "")
    case "$(uname -s)" in
      Darwin) host="thomas-darwin" ;;
      Linux)  host="thomas-linux"  ;;
      *)      printf 'error: unsupported OS %s. Set DOTFILES_HOST.\n' "$(uname -s)" >&2; exit 1 ;;
    esac
    ;;
  *) host="$DOTFILES_HOST" ;;
esac

# Several config/<tool>/ directories use git submodules for catppuccin
# themes (alacritty, bat, eza, fzf, mako, rofi, waybar, yazi, zellij).
# `git+file://?submodules=1` runs `git ls-files --recurse-submodules`
# so submodule contents make it into the Nix store; plain `path:` does
# not support that flag and would leave e.g. ~/.config/fzf/catppuccin
# missing.
flake_ref="git+file://$DOTFILES?submodules=1#homeConfigurations.$host.activationPackage"

printf '==> Building home-manager generation for %s\n' "$host"
out=$(nix \
  --extra-experimental-features 'nix-command flakes' \
  build --impure --no-link --print-out-paths \
  "$flake_ref")

printf '==> Activating %s\n' "$out/activate"
"$out/activate"
