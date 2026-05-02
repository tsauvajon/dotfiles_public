#!/usr/bin/env bash
# To enable private setup (git identity, network config):
#
#   cp dotfiles.example.toml ~/.config/dotfiles/config.toml
#   $EDITOR ~/.config/dotfiles/config.toml
#   bash setup.sh
#
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export DOTFILES

if command -v nix >/dev/null 2>&1; then
  exec nix run "path:$DOTFILES" -- "$@"
elif command -v cargo >/dev/null 2>&1; then
  exec cargo run --quiet --manifest-path "$DOTFILES/Cargo.toml" -- "$@"
else
  printf 'error: neither nix nor cargo found on PATH.\n' >&2
  printf 'Install Nix (https://nixos.org) or Rust (https://rustup.rs) first.\n' >&2
  exit 1
fi
