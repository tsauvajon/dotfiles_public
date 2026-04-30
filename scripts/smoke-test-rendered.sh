#!/usr/bin/env bash
# Smoke test: dump a content-addressed manifest of the rendered $HOME state
# produced by `setup.sh` against an ephemeral home directory.
#
# Run twice — once on the baseline, once on the candidate branch — and `diff`
# the two manifests. Symlink target strings will differ; the resolved file
# contents (sha256) and reachable directory tree must match.
#
#   ./scripts/smoke-test-rendered.sh /tmp/before.txt
#   ./scripts/smoke-test-rendered.sh /tmp/after.txt
#   diff -u /tmp/before.txt /tmp/after.txt
#
# Expected residual diff when comparing across a submodule move: the per-
# submodule `.git` pointer files (`./.tmux/plugins/<sm>/.git`) literally
# contain `gitdir: …/<path>` strings, so they change content whenever a
# submodule worktree path moves. Everything else must match byte-for-byte.
set -euo pipefail

out=${1:?usage: smoke-test-rendered.sh <manifest-path>}
out=$(cd "$(dirname "$out")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$out")")

DOTFILES=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)

# Pin CARGO_HOME to the host's real cargo home so cargo doesn't pollute the
# ephemeral $HOME_DIR with its registry cache (which would also flap between
# runs and bury our setup output in noise).
ORIG_CARGO_HOME=${CARGO_HOME:-$HOME/.cargo}

HOME_DIR=$(mktemp -d)
DEV_DIR=$(mktemp -d)
trap 'rm -rf "$HOME_DIR" "$DEV_DIR"' EXIT

# Strip nix and task from PATH so external setup steps no-op gracefully:
#   - the setup tool only mutates the user's nix profile if `which nix` succeeds
#   - it only runs `task bootstrap` if $HOME/.cargo/bin/task exists (it won't)
# We keep the directory containing cargo on PATH so the build still resolves.
cargo_dir=$(dirname "$(command -v cargo)")
SAFE_PATH="$cargo_dir:/usr/bin:/bin"
# Drop any /nix/... or task entries from PATH; keep the rest.
clean_path=$(printf '%s' "$PATH" | tr ':' '\n' \
  | grep -v -E '^/nix/' \
  | grep -v -F "$HOME/.cargo/bin" \
  | paste -sd: -)
HOME="$HOME_DIR" DEV_ROOT="$DEV_DIR" DOTFILES="$DOTFILES" \
  CARGO_HOME="$ORIG_CARGO_HOME" \
  PATH="$SAFE_PATH:$clean_path" \
  cargo run --quiet --manifest-path "$DOTFILES/Cargo.toml" -- >/dev/null

# `find -L` follows symlinks so the tmux layout change (real dir vs symlink)
# is normalised — both produce the same set of files underneath.
{
  cd "$HOME_DIR"
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
