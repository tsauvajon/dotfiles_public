#!/usr/bin/env bash
# Bootstrap the dotfiles via Home Manager.
#
# 1. Verifies Nix is installed.
# 2. Resolves the host attribute. Defaults: macOS -> thomas-darwin,
#    Linux -> thomas-linux. Override with $DOTFILES_HOST.
# 3. Reads opencode.imports from the private flake and syncs each
#    listed source into ~/.config/dotfiles/opencode-imports/<name>/
#    so external (non-Nix) repos can contribute partial OpenCode
#    config (commands, skills, plugins, opencode.*.json fragments,
#    rules) without absolute symlinks that break Nix purity.
# 4. Builds homeConfigurations.<host>.activationPackage from this
#    flake (with --override-input private "path:..." so the working
#    tree of the private overlay is used, including the staged
#    imports tree which is gitignored) and runs the resulting
#    `activate` script.
#
# The activation block in home/bootstrap.nix takes care of:
#   - cleaning up legacy symlinks the previous Rust setup tool created
#   - removing the obsolete ~/.config/dotfiles/path file
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
private_ref="$HOME/.config/dotfiles"

if [ ! -f "$private_ref/flake.nix" ]; then
  printf 'error: private config not found at %s\n' "$private_ref" >&2
  printf 'Create it from the example or skip if your host does not require private data.\n' >&2
  exit 1
fi

# nixGL uses builtins.currentTime which requires --impure on Linux
IMPURE_FLAG=""
if [ "$(uname -s)" = "Linux" ]; then
  IMPURE_FLAG="--impure"
fi

# Sync external OpenCode imports declared in the private flake's
# `opencode.imports` list into ~/.config/dotfiles/opencode-imports/.
# The list is rendered to a tab-separated stream by Nix itself so we
# do not depend on jq being installed.
#
# Stream format (one record per line):
#   <name>\t<source>\t<kind>\t<src-rel>\t<dest-rel>
# where <kind> is "file" or "dir".
sync_opencode_imports() {
  local manifest stage source name kind src dest abs_src abs_dest
  local sync_root="$private_ref/opencode-imports"

  # Render the manifest. If the private flake has no imports (or fails
  # to evaluate), proceed silently with no sync.
  if ! manifest=$(nix \
    --extra-experimental-features 'nix-command flakes' \
    eval --raw --no-write-lock-file \
    "path:$private_ref#opencode.imports" \
    --apply '
      imports:
        let
          fmt = name: source: kind: e:
            "${name}\t${source}\t${kind}\t${e.src}\t${e.dest or e.src}";
          formatImport = i:
            builtins.concatStringsSep "\n" (
              (builtins.map (fmt i.name i.source "file") (i.files or []))
              ++
              (builtins.map (fmt i.name i.source "dir")  (i.dirs  or []))
            );
          lines = builtins.filter (s: s != "") (builtins.map formatImport imports);
        in
          builtins.concatStringsSep "\n" lines
    ' 2>/dev/null); then
    # Eval failed (likely the private flake has no `opencode.imports`
    # attribute). Leave any existing staging untouched so a transient
    # nix error does not silently strip imports from the build.
    return 0
  fi

  # Eval succeeded — reset the staging root so removed manifest entries
  # do not linger.
  rm -rf "$sync_root"

  if [ -z "$manifest" ]; then
    return 0
  fi

  mkdir -p "$sync_root"
  printf '==> Syncing OpenCode imports into %s\n' "$sync_root"

  while IFS=$'\t' read -r name source kind src dest; do
    [ -z "$name" ] && continue
    # Tilde expansion (Nix passes the source as-is from the manifest).
    case "$source" in
      "~"|"~/"*) source="$HOME${source#\~}" ;;
    esac
    abs_src="$source/$src"
    abs_dest="$sync_root/$name/$dest"

    case "$kind" in
      file)
        if [ ! -f "$abs_src" ]; then
          printf 'warning: opencode-import "%s" missing file: %s\n' "$name" "$abs_src" >&2
          continue
        fi
        mkdir -p "$(dirname "$abs_dest")"
        cp -L "$abs_src" "$abs_dest"
        ;;
      dir)
        if [ ! -d "$abs_src" ]; then
          printf 'warning: opencode-import "%s" missing dir: %s\n' "$name" "$abs_src" >&2
          continue
        fi
        mkdir -p "$(dirname "$abs_dest")"
        # cp -RL dereferences symlinks, producing a clean tree of
        # regular files inside the staging area.
        cp -RL "$abs_src" "$abs_dest"
        ;;
      *)
        printf 'warning: opencode-import "%s" unknown kind "%s"\n' "$name" "$kind" >&2
        ;;
    esac
  done <<<"$manifest"
}

sync_opencode_imports

printf '==> Building home-manager generation for %s\n' "$host"
out=$(nix \
  --extra-experimental-features 'nix-command flakes' \
  build $IMPURE_FLAG --no-link --no-write-lock-file --print-out-paths \
  --override-input private "path:$private_ref" \
  "$flake_ref")

printf '==> Activating %s/activate\n' "$out"
"$out/activate"
