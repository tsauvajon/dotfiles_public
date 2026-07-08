#!/usr/bin/env bash
# Reconcile Arch Linux packages declared in packages/arch/pacman.txt.
set -euo pipefail

mode=install
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
manifest="$DOTFILES/packages/arch/pacman.txt"

usage() {
  cat <<EOF
Usage: scripts/arch-packages.sh [--check|--install]

Installs packages declared in:
  $manifest

Default mode is --install. --check lists missing packages and exits 1 when any
managed package is not installed.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --check)
      mode=check
      ;;
    --install)
      mode=install
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

if ! command -v pacman >/dev/null 2>&1; then
  printf 'pacman not found; skipping managed Arch packages.\n'
  exit 0
fi

if [ ! -f "$manifest" ]; then
  printf 'error: pacman package manifest not found: %s\n' "$manifest" >&2
  exit 1
fi

packages=()
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"
  read -r package _ <<<"$line" || true
  [ -n "${package:-}" ] && packages+=("$package")
done < "$manifest"

if [ "${#packages[@]}" -eq 0 ]; then
  printf 'No managed Arch packages declared.\n'
  exit 0
fi

missing=()
for package in "${packages[@]}"; do
  if ! pacman -Qi "$package" >/dev/null 2>&1; then
    missing+=("$package")
  fi
done

if [ "${#missing[@]}" -eq 0 ]; then
  printf 'All managed Arch packages are installed.\n'
  exit 0
fi

if [ "$mode" = "check" ]; then
  printf 'Missing managed Arch packages:\n'
  for package in "${missing[@]}"; do
    printf '  %s\n' "$package"
  done
  exit 1
fi

printf '==> Installing missing managed Arch packages with pacman\n'
if [ "$(id -u)" -eq 0 ]; then
  pacman -S --needed "${missing[@]}"
else
  if ! command -v sudo >/dev/null 2>&1; then
    printf 'error: sudo not found; cannot install missing Arch packages\n' >&2
    exit 1
  fi
  sudo pacman -S --needed "${missing[@]}"
fi
