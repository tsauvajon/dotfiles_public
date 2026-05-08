#!/usr/bin/env bash
# Smoke test: build the home-manager activationPackage for a host
# (without running `activate`) and dump a content-addressed manifest
# of every file the activation would link into $HOME.
#
# Run twice — once on the baseline, once on the candidate branch — and
# diff the two manifests. Symlink target strings will differ; the
# resolved file contents (sha256) and reachable directory tree must
# match.
#
#   ./scripts/smoke-test-rendered.sh /tmp/before.txt
#   ./scripts/smoke-test-rendered.sh /tmp/after.txt
#   diff -u /tmp/before.txt /tmp/after.txt
#
# Optional second argument selects the host (defaults to the same
# auto-detection setup.sh uses). Override the private flake source via
# DOTFILES_PRIVATE_REF (defaults to ~/.config/dotfiles).
#
# Expected residual diff when comparing across a submodule move: the
# per-submodule `.git` pointer files (`./.tmux/plugins/<sm>/.git`)
# literally contain `gitdir: …/<path>` strings, so they change content
# whenever a submodule worktree path moves. Everything else must match
# byte-for-byte.
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  printf 'usage: %s <manifest-path> [host]\n' "$(basename "$0")" >&2
  exit 64
fi

out=$1
out=$(cd "$(dirname "$out")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$out")")

DOTFILES=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

case "${2:-}" in
  "")
    case "$(uname -s)" in
      Darwin)
        case "$(uname -m)" in
          arm64)  host="thomas-darwin" ;;
          x86_64) host="thomas-darwin-intel" ;;
          *)      printf 'error: unsupported Darwin arch %s. Pass host explicitly.\n' "$(uname -m)" >&2; exit 1 ;;
        esac
        ;;
      Linux) host="thomas-linux" ;;
      *)     printf 'error: unsupported OS %s. Pass host explicitly.\n' "$(uname -s)" >&2; exit 1 ;;
    esac
    ;;
  *) host="$2" ;;
esac

private_ref="${DOTFILES_PRIVATE_REF:-$HOME/.config/dotfiles}"
flake_ref="path:$DOTFILES#homeConfigurations.$host.activationPackage"

if [ ! -f "$private_ref/flake.nix" ]; then
  printf 'error: private flake missing at %s/flake.nix\n' "$private_ref" >&2
  printf '       run setup.sh first or set DOTFILES_PRIVATE_REF\n' >&2
  exit 1
fi

printf 'building %s for %s\n' "$flake_ref" "$host" >&2

# `--no-link` keeps the working tree clean; `--print-out-paths` gives
# us the store path of the activation package so we can walk its
# `home-files` subtree (which mirrors the layout HM would link into
# $HOME) without ever invoking `activate`. `SMOKE_TEST_IMPURE=1`
# turns on `--impure`, useful when the private flake references
# `~/...` paths that pure mode cannot resolve.
impure_flag=()
if [ "${SMOKE_TEST_IMPURE:-0}" = "1" ]; then
  impure_flag=(--impure)
fi

result=$(nix \
  --extra-experimental-features 'nix-command flakes' \
  build --no-link --no-write-lock-file --print-out-paths \
  "${impure_flag[@]}" \
  --override-input private "path:$private_ref" \
  "$flake_ref")

home_files="$result/home-files"
if [ ! -d "$home_files" ]; then
  printf 'error: no home-files subtree in %s\n' "$result" >&2
  exit 1
fi

# `find -L` follows symlinks so the rendered tree is normalised — both
# real files and symlinks-to-real-files produce the same manifest.
{
  cd "$home_files"
  find -L . -type f -print0 \
    | LC_ALL=C sort -z \
    | while IFS= read -r -d '' f; do
        sum=$(shasum -a 256 "$f" | cut -d' ' -f1)
        printf '%s\tfile\t%s\n' "$f" "$sum"
      done
  find -L . -type d -print0 \
    | LC_ALL=C sort -z \
    | while IFS= read -r -d '' d; do
        printf '%s\tdir\t-\n' "$d"
      done
} > "$out"

printf 'wrote manifest: %s (%d entries)\n' "$out" "$(wc -l < "$out")" >&2
