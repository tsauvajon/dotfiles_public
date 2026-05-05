#!/usr/bin/env bash
# Bootstrap the dotfiles via Home Manager.
#
# 1. Verifies Nix is installed.
# 2. Resolves the host attribute. Defaults: macOS -> thomas-darwin,
#    Linux -> thomas-linux. Override with $DOTFILES_HOST.
# 3. Builds homeConfigurations.<host>.activationPackage from this flake
#    and runs the resulting `activate` script.
#
# The activation block in home/bootstrap.nix takes care of:
#   - recording this repo's path at ~/.config/dotfiles/path
#   - cleaning up legacy symlinks the previous Rust setup tool created
#   - running `task bootstrap` so workspace dirs are ready
#
# To preview without activating, use:
#   nix --extra-experimental-features 'nix-command flakes' \
#     build --impure --dry-run \
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

flake_ref="path:$DOTFILES#homeConfigurations.$host.activationPackage"

printf '==> Building home-manager generation for %s\n' "$host"
out=$(nix \
  --extra-experimental-features 'nix-command flakes' \
  build --impure --no-link --print-out-paths \
  "$flake_ref")

printf '==> Activating %s\n' "$out/activate"
"$out/activate"
