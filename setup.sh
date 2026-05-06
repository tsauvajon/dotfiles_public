#!/usr/bin/env bash
# Bootstrap the dotfiles via Home Manager.
#
# 1. Verifies Nix is installed.
# 2. Resolves the host attribute. Defaults: macOS -> thomas-darwin,
#    Linux -> thomas-linux. Override with $DOTFILES_HOST.
# 3. Auto-bootstraps ~/.config/dotfiles/flake.nix from
#    private.example.nix on first run when missing, then exits so
#    the user can edit the placeholders before the actual build.
# 4. Reads opencode.imports from the private flake and syncs each
#    listed source into ~/.config/dotfiles/opencode-imports/<name>/
#    so external (non-Nix) repos can contribute partial OpenCode
#    config (commands, skills, plugins, opencode.*.json fragments,
#    rules) without absolute symlinks that break Nix purity.
# 5. Builds homeConfigurations.<host>.activationPackage from this
#    flake (with --override-input private "path:..." so the working
#    tree of the private overlay is used, including the staged
#    imports tree which is gitignored) and runs the resulting
#    `activate` script.
#
# The activation block in home/bootstrap.nix takes care of:
#   - removing managed symlinks before checkLinkTargets runs
#   - removing the unused ~/.config/dotfiles/path file if present
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
      Darwin)
        case "$(uname -m)" in
          arm64)  host="thomas-darwin" ;;
          x86_64) host="thomas-darwin-intel" ;;
          *)      printf 'error: unsupported Darwin arch %s. Set DOTFILES_HOST.\n' "$(uname -m)" >&2; exit 1 ;;
        esac
        ;;
      Linux)  host="thomas-linux"  ;;
      *)      printf 'error: unsupported OS %s. Set DOTFILES_HOST.\n' "$(uname -s)" >&2; exit 1 ;;
    esac
    ;;
  *) host="$DOTFILES_HOST" ;;
esac

flake_ref="path:$DOTFILES#homeConfigurations.$host.activationPackage"
private_ref="$HOME/.config/dotfiles"
example_ref="$DOTFILES/private.example.nix"

if [ ! -f "$private_ref/flake.nix" ]; then
  if [ ! -f "$example_ref" ]; then
    printf 'error: private flake missing at %s/flake.nix and example template missing at %s\n' \
      "$private_ref" "$example_ref" >&2
    exit 1
  fi
  printf '==> No private flake at %s/flake.nix\n' "$private_ref"
  printf '==> Bootstrapping from %s\n' "$example_ref"
  mkdir -p "$private_ref"
  cp "$example_ref" "$private_ref/flake.nix"
  cat <<EOF

Next steps:
  1. \$EDITOR $private_ref/flake.nix
  2. fill in the git.{name,email,signingKey} placeholders (required)
  3. rerun ./setup.sh

Anything optional (goto, opencode overlays, homeModules) can stay null.

Need a GPG signing key? Generate one without installing anything globally:

  nix --extra-experimental-features 'nix-command flakes' run nixpkgs#gnupg -- \\
    --quick-generate-key "Your Name <you@example.com>" ed25519 default 1y
  nix --extra-experimental-features 'nix-command flakes' run nixpkgs#gnupg -- \\
    --list-secret-keys --keyid-format long

Copy the 16-char hex after \`sec ed25519/...\` into git.signingKey.
(Use rsa4096 instead of ed25519 for broader compatibility.)
EOF
  exit 0
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
  local manifest stage source name kind src dest abs_src abs_dest stderr_file
  local sync_root="$private_ref/opencode-imports"

  stderr_file=$(mktemp -t dotfiles-imports-stderr.XXXXXX)

  # Render the manifest. If the private flake has no `opencode.imports`
  # attribute, that is a normal "no imports declared" state — silently
  # proceed. Other eval errors (syntax, missing inputs, network
  # failures) get surfaced to stderr so the user notices stale staging.
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
    ' 2>"$stderr_file"); then
    if grep -qE "(does not provide attribute|attribute '?opencode'?)" "$stderr_file"; then
      # Expected: private flake has no imports manifest. Leave any
      # existing staging untouched.
      rm -f "$stderr_file"
      return 0
    fi
    printf 'warning: failed to read opencode.imports from private flake:\n' >&2
    cat "$stderr_file" >&2
    rm -f "$stderr_file"
    # Existing staging stays in place rather than being wiped on a
    # transient eval error.
    return 0
  fi
  rm -f "$stderr_file"

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
    # Only `~` and `~/...` are supported; the `~user/...` form would
    # require user-database lookup and is not worth the complexity.
    case "$source" in
      "~"|"~/"*) source="$HOME${source#\~}" ;;
      "~"*)
        printf 'warning: opencode-import "%s" uses unsupported ~user/ form: %s\n' "$name" "$source" >&2
        continue
        ;;
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
        # `cp -R src dst` copies *into* dst when dst already exists,
        # producing a nested tree on a second sync. The early-return
        # path above can leave a stale dest behind on the first run,
        # so wipe it explicitly to keep the operation idempotent.
        rm -rf "$abs_dest"
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

# Optional pre-build hook from the private overlay. Sourced (not
# executed) so it can mutate this script's environment — typical use
# is to extend NIX_CONFIG with extra substituters or impure-env vars
# that must not live in the public repo. Absent on hosts that don't
# need it.
if [ -f "$private_ref/pre-build.sh" ]; then
  # shellcheck disable=SC1091
  . "$private_ref/pre-build.sh"
fi

printf '==> Building home-manager generation for %s\n' "$host"
out=$(nix \
  --extra-experimental-features 'nix-command flakes' \
  build $IMPURE_FLAG --no-link --no-write-lock-file --print-out-paths \
  --override-input private "path:$private_ref" \
  "$flake_ref")

printf '==> Activating %s/activate\n' "$out"
"$out/activate"
