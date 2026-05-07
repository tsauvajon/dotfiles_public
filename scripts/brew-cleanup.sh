#!/usr/bin/env bash
# Dry-run cleanup for Homebrew casks not declared in config/Brewfile.
set -euo pipefail

apply=0
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
brewfile="$DOTFILES/config/Brewfile"

usage() {
  cat <<EOF
Usage: scripts/brew-cleanup.sh [--apply]

Lists installed Homebrew casks that are not declared in config/Brewfile.
By default this is a dry run. Pass --apply to uninstall the extra casks.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --apply)
      apply=1
      ;;
    --dry-run)
      apply=0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'error: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$(uname -s)" != "Darwin" ]; then
  printf 'Homebrew cask cleanup is only supported on macOS.\n'
  exit 0
fi

if ! command -v brew >/dev/null 2>&1; then
  printf 'error: brew not found on PATH\n' >&2
  exit 1
fi

if [ ! -f "$brewfile" ]; then
  printf 'error: Brewfile not found: %s\n' "$brewfile" >&2
  exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

wanted="$tmpdir/wanted-casks"
installed="$tmpdir/installed-casks"
extras="$tmpdir/extra-casks"

sed -nE 's/^[[:space:]]*cask[[:space:]]+"([^"]+)".*/\1/p' "$brewfile" | sort -u > "$wanted"
brew list --cask -1 | sort -u > "$installed"
comm -23 "$installed" "$wanted" > "$extras"

if [ ! -s "$extras" ]; then
  printf 'No extra Homebrew casks found.\n'
  exit 0
fi

if [ "$apply" -eq 0 ]; then
  printf 'Extra Homebrew casks not declared in %s:\n' "$brewfile"
  while IFS= read -r cask; do
    printf '  %s\n' "$cask"
  done < "$extras"
  printf '\nDry run only. Pass --apply to uninstall these casks.\n'
  exit 0
fi

while IFS= read -r cask; do
  [ -z "$cask" ] && continue
  brew uninstall --cask "$cask"
done < "$extras"
