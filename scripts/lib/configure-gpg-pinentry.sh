#!/usr/bin/env bash
# Idempotently set the `pinentry-program` line in a gpg-agent.conf.
#
# Usage:
#   configure-gpg-pinentry.sh <conf-path> <pinentry-program-path>
#
# Behaviour:
#   - Creates the parent directory with mode 700 if missing.
#   - Replaces a /nix/store-pointing symlink with a mutable file
#     (the activation script previously installed such a symlink on
#     some hosts; we keep this branch so a fresh activation does not
#     try to rewrite a read-only store path).
#   - Drops every existing `pinentry-program` line and appends a
#     single fresh one with the supplied path. All other settings in
#     the conf (cache TTLs, etc.) are preserved.
#
# The helper is shape-agnostic: missing file, empty file, single
# pinentry line, or multiple stale pinentry lines all converge to the
# same final state — exactly one `pinentry-program <path>` line plus
# every other line untouched.
set -euo pipefail
umask 077

if [ "$#" -ne 2 ]; then
  printf 'usage: %s <conf-path> <pinentry-program-path>\n' "$(basename "$0")" >&2
  exit 64
fi

conf="$1"
pinentry_program="$2"

if [ -z "$conf" ] || [ -z "$pinentry_program" ]; then
  printf 'error: conf path and pinentry program must both be non-empty\n' >&2
  exit 64
fi

pinentry_line="pinentry-program $pinentry_program"
gnupg_dir=$(dirname "$conf")

mkdir -p "$gnupg_dir"
chmod 700 "$gnupg_dir"

# A symlink left behind by an earlier home-manager generation can
# point into the read-only Nix store, which would defeat the rewrite
# below. Drop it so the redirect creates a fresh mutable file.
if [ -L "$conf" ]; then
  target=$(readlink "$conf" 2>/dev/null || true)
  case "$target" in
    /nix/store/*) rm -f "$conf" ;;
  esac
fi

# Filter existing `pinentry-program` lines, then append one fresh
# line. `grep -v` returns 1 when the input is empty or has no
# matches; suppress that with `|| true` so set -e does not fire.
tmp="$conf.tmp.$$"
{
  grep -v '^pinentry-program ' "$conf" 2>/dev/null || true
  printf '%s\n' "$pinentry_line"
} > "$tmp"
mv "$tmp" "$conf"
