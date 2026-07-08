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
# 5. Bootstraps missing per-machine GPG/SSH keys from the private git
#    identity and fills git.signingKey when it can do so safely.
# 6. Installs missing Arch packages from packages/arch/pacman.txt when
#    pacman is available.
# 7. Builds homeConfigurations.<host>.activationPackage from this
#    flake (with --override-input private "path:..." so the working
#    tree of the private overlay is used, including the staged
#    imports tree which is gitignored) and runs the resulting
#    `activate` script.
#
# The activation block in home/bootstrap.nix takes care of:
#   - removing managed symlinks before checkLinkTargets runs
#   - running `task bootstrap` so workspace dirs are ready
#
# To preview without activating, use:
#   nix --extra-experimental-features 'nix-command flakes' \
#     build --dry-run \
#     "path:.#homeConfigurations.<host>.activationPackage"
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export DOTFILES

# shellcheck source=scripts/lib/opencode-imports.sh
. "$DOTFILES/scripts/lib/opencode-imports.sh"

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

  # Fully scripted first-run path: when both DOTFILES_GIT_NAME and
  # DOTFILES_GIT_EMAIL are set, scripts/bootstrap-keys.sh below will
  # patch them into the freshly-copied flake (along with signingKey
  # after generating the key). Skip the "edit and rerun" exit and
  # continue straight into the build.
  if [ -n "${DOTFILES_GIT_NAME:-}" ] && [ -n "${DOTFILES_GIT_EMAIL:-}" ]; then
    printf '==> Seeding git.name / git.email from env vars; continuing to build\n'
  else
    cat <<EOF

Next steps:
  1. \$EDITOR $private_ref/flake.nix
  2. fill in git.{name,email}; leave git.signingKey empty if you need a new key
  3. rerun ./setup.sh

Or run a fully scripted first install:
  DOTFILES_GIT_NAME="Your Full Name" \\
  DOTFILES_GIT_EMAIL="you@example.com" \\
  ./setup.sh

Anything optional (goto, opencode overlays, homeModules) can stay null.

On the next run, setup.sh will generate missing GPG/SSH keys, fill
git.signingKey when safe, and print public-key upload commands.
EOF
    exit 0
  fi
fi

# Sync external OpenCode imports declared in the private flake's
# `opencode.imports` list into ~/.config/dotfiles/opencode-imports/.
#
# Per-import schema (every field except `name` and `source` is
# optional; mutually-exclusive combinations are rejected at run time):
#
#   name     staging dir name under ~/.config/dotfiles/opencode-imports/
#   source   path to the source repo (supports leading ~ / ~/...)
#   rename   { "<src-rel>" = "<dest-rel>"; ... }
#            Renames an auto-discovered item, OR adds a non-standard
#            file (one not picked up by auto-discovery).
#   exclude  [ "<src-rel>" ... ]
#            Source-rel paths to skip during auto-discovery.
#   paths    { "<src-rel>" = "<dest-rel>"; ... }
#            Cherry-pick mode: when set, auto-discovery is OFF and
#            ONLY these mappings are imported. Mutually exclusive
#            with `rename` and `exclude`.
#
# Auto-discovery (when `paths` is unset) picks up:
#   - Every entry under commands/, skills/, agents/, plugins/, rules/
#     in the source root (file or dir, copied verbatim).
#   - Top-level files matching `opencode.*.json` (excluding the bare
#     `opencode.json`) and `package.json`.
# Then `exclude` filters that list and `rename` rewrites destinations.
# Finally any rename entries pointing at non-standard sources (e.g.
# mcp.fragment.json) are imported as-is.
#
# The schema is rendered to a tab-separated record stream by Nix
# itself so we do not depend on jq being installed. Bash parses the
# stream, expands `~` in `source`, walks the tree, and stages files.
#
# Record types (first field):
#   HEADER  <name>  <source>  <mode>           mode = auto | explicit
#   RENAME  <name>  <src>     <dest>
#   EXCLUDE <name>  <src>
#   PATH    <name>  <src>     <dest>
#   END     <name>
sync_opencode_imports() {
  local manifest stderr_file
  local sync_root="$private_ref/opencode-imports"

  stderr_file=$(mktemp -t dotfiles-imports-stderr.XXXXXX)

  # shellcheck disable=SC2016
  if ! manifest=$(nix \
    --extra-experimental-features 'nix-command flakes' \
    eval --raw --no-write-lock-file \
    "path:$private_ref#opencode.imports" \
    --apply '
      imports:
        let
          hasTabOrNewline = s: builtins.match ".*[\t\n].*" s != null;
          checked = label: s:
            if hasTabOrNewline s
            then builtins.throw "opencode.imports ${label} contains a tab or newline"
            else s;
          fmtImport = i:
            let
              name       = checked "name" i.name;
              source     = checked "source for ${name}" i.source;
              rename     = i.rename or {};
              exclude    = i.exclude or [];
              hasPaths   = i ? paths;
              paths      = i.paths or {};
              mode       = if hasPaths then "explicit" else "auto";
              header     = "HEADER\t${name}\t${source}\t${mode}";
              renameLines = builtins.map
                (k:
                  let
                    src = checked "rename key for ${name}" k;
                    dest = checked "rename value for ${name}.${src}" rename.${k};
                  in
                    "RENAME\t${name}\t${src}\t${dest}")
                (builtins.attrNames rename);
              excludeLines = builtins.map
                (s: "EXCLUDE\t${name}\t${checked "exclude entry for ${name}" s}")
                exclude;
              pathLines = builtins.map
                (k:
                  let
                    src = checked "paths key for ${name}" k;
                    dest = checked "paths value for ${name}.${src}" paths.${k};
                  in
                    "PATH\t${name}\t${src}\t${dest}")
                (builtins.attrNames paths);
              footer = "END\t${name}";
            in
              builtins.concatStringsSep "\n"
                ([ header ] ++ renameLines ++ excludeLines ++ pathLines ++ [ footer ]);
        in
          builtins.concatStringsSep "\n" (builtins.map fmtImport imports)
    ' 2>"$stderr_file"); then
    if grep -qE "(does not provide attribute .*'(opencode|opencode\.imports|imports)'|attribute '?(opencode|imports)'? missing)" "$stderr_file"; then
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

  opencode_imports_sync "$sync_root" <<<"$manifest"
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

"$DOTFILES/scripts/bootstrap-keys.sh"

if command -v pacman >/dev/null 2>&1; then
  "$DOTFILES/scripts/arch-packages.sh" --install
fi

printf '==> Building home-manager generation for %s\n' "$host"
# `--max-jobs auto --cores 0` parallelises the very first build, before
# the HM-managed ~/.config/nix/nix.conf (config/nix/nix.conf) is in
# place. After activation, those defaults are picked up from nix.conf
# and the flags become harmless redundancy.
out=$(nix \
  --extra-experimental-features 'nix-command flakes' \
  --max-jobs auto --cores 0 \
  build --no-link --no-write-lock-file --print-out-paths \
  --override-input private "path:$private_ref" \
  "$flake_ref")

printf '==> Activating %s/activate\n' "$out"
"$out/activate"

if [ -x "/opt/homebrew/bin/brew" ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x "/usr/local/bin/brew" ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# Declarative casks (Darwin only). The reconciler below installs casks
# declared in the listed Brewfiles with Homebrew. setup.sh never
# invokes package installs with sudo itself.
#
# Two Brewfiles are reconciled on Darwin:
#   1. `$DOTFILES/config/Brewfile` — public, hand-edited base file.
#   2. `~/.config/dotfiles-managed/Brewfile.personal` — generated by
#      `home/personal.nix` from `dotfiles.personal.*` toggles. Absent
#      on work machines and on hosts with no personal cask selected;
#      Home Manager removes the symlink when the toggle flips off and
#      `scripts/brew-cleanup.sh --apply` then uninstalls the package.
if [ "$(uname -s)" = "Darwin" ]; then
  # `Brewfile.personal` is generated by `home/personal.nix` via
  # `xdg.configFile`. This dotfiles config leaves Home Manager's
  # `xdg.configHome` at its default, so the generated file is expected
  # under `$HOME/.config`.
  brewfiles=(
    "$DOTFILES/config/Brewfile"
    "$HOME/.config/dotfiles-managed/Brewfile.personal"
  )

  managed_casks=0
  for brewfile in "${brewfiles[@]}"; do
    if [ -f "$brewfile" ] && grep -Eq '^[[:space:]]*cask[[:space:]]+"' "$brewfile"; then
      managed_casks=1
      break
    fi
  done

  if [ "$managed_casks" -eq 1 ]; then
    if command -v brew >/dev/null 2>&1; then
      brew update

      for brewfile in "${brewfiles[@]}"; do
        if [ -f "$brewfile" ]; then
          printf '==> Installing managed casks from %s with Homebrew\n' "$brewfile"
          brew bundle install --file="$brewfile"
        fi
      done

      # Uninstall any Homebrew cask that is currently installed but absent
      # from both Brewfiles. This keeps personal toggles reconciled when they
      # are turned off.
      "$DOTFILES/scripts/brew-cleanup.sh" --apply
    else
      printf '\n'
      printf 'warning: Homebrew not found; skipping managed casks. To install manually, run:\n'
      # shellcheck disable=SC2016
      printf '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"\n'
      printf '\n'
    fi
  fi
fi
