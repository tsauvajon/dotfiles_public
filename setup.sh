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
# 6. Builds homeConfigurations.<host>.activationPackage from this
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
          fmtImport = i:
            let
              rename     = i.rename or {};
              exclude    = i.exclude or [];
              hasPaths   = i ? paths;
              paths      = i.paths or {};
              mode       = if hasPaths then "explicit" else "auto";
              header     = "HEADER\t${i.name}\t${i.source}\t${mode}";
              renameLines = builtins.map
                (k: "RENAME\t${i.name}\t${k}\t${rename.${k}}")
                (builtins.attrNames rename);
              excludeLines = builtins.map
                (s: "EXCLUDE\t${i.name}\t${s}")
                exclude;
              pathLines = builtins.map
                (k: "PATH\t${i.name}\t${k}\t${paths.${k}}")
                (builtins.attrNames paths);
              footer = "END\t${i.name}";
            in
              builtins.concatStringsSep "\n"
                ([ header ] ++ renameLines ++ excludeLines ++ pathLines ++ [ footer ]);
        in
          builtins.concatStringsSep "\n" (builtins.map fmtImport imports)
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

  # Per-import accumulators (reset on each HEADER, consumed on END).
  local cur_name="" cur_source="" cur_mode=""
  local -a cur_rename_src=() cur_rename_dest=()
  local -a cur_exclude=()
  local -a cur_path_src=() cur_path_dest=()

  local tag a b c
  while IFS=$'\t' read -r tag a b c; do
    [ -z "$tag" ] && continue
    case "$tag" in
      HEADER)
        cur_name="$a" cur_source="$b" cur_mode="$c"
        cur_rename_src=() cur_rename_dest=()
        cur_exclude=()
        cur_path_src=() cur_path_dest=()
        ;;
      RENAME)
        cur_rename_src+=("$b") cur_rename_dest+=("$c")
        ;;
      EXCLUDE)
        cur_exclude+=("$b")
        ;;
      PATH)
        cur_path_src+=("$b") cur_path_dest+=("$c")
        ;;
      END)
        process_import
        ;;
      *)
        printf 'warning: unknown opencode-import record tag %q\n' "$tag" >&2
        ;;
    esac
  done <<<"$manifest"
}

# Stage src→dst as either a file or a directory copy. cp -L /-RL
# dereferences symlinks so the staging area is a clean tree of regular
# files. `cp -R src dst` copies *into* dst when dst already exists, so
# we wipe an existing destination first to keep the sync idempotent.
stage_one() {
  local src="$1" dst="$2" name="$3"
  if [ -d "$src" ]; then
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -RL "$src" "$dst"
  elif [ -f "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -L "$src" "$dst"
  else
    printf 'warning: opencode-import "%s" missing path: %s\n' "$name" "$src" >&2
  fi
}

# Membership check against the cur_exclude array.
import_excluded() {
  local rel="$1" i
  for ((i = 0; i < ${#cur_exclude[@]}; i++)); do
    [ "${cur_exclude[$i]}" = "$rel" ] && return 0
  done
  return 1
}

# Print the rename destination for a source-rel path, or the path
# itself when no rename rule matches.
import_rename_for() {
  local rel="$1" i
  for ((i = 0; i < ${#cur_rename_src[@]}; i++)); do
    if [ "${cur_rename_src[$i]}" = "$rel" ]; then
      printf '%s' "${cur_rename_dest[$i]}"
      return 0
    fi
  done
  printf '%s' "$rel"
}

# Process the import described by the cur_* state. Validates schema,
# expands `~` in source, then either cherry-picks (explicit mode) or
# walks the standard layout (auto mode).
process_import() {
  local source="$cur_source"

  # Tilde expansion. Only `~` and `~/...` are supported; the
  # `~user/...` form would require user-database lookup.
  # shellcheck disable=SC2088
  case "$source" in
    "~"|"~/"*) source="$HOME${source#\~}" ;;
    "~"*)
      printf 'warning: opencode-import "%s" uses unsupported ~user/ form: %s\n' "$cur_name" "$source" >&2
      return 0
      ;;
  esac

  local stage="$private_ref/opencode-imports/$cur_name"
  mkdir -p "$stage"

  # Mutual-exclusion validation: `paths` cannot mix with rename/exclude.
  # Misconfiguration is fatal — make the user fix the flake before any
  # downstream nix build runs against an inconsistent staging tree.
  if [ "$cur_mode" = "explicit" ]; then
    if [ ${#cur_rename_src[@]} -gt 0 ]; then
      printf 'error: opencode-import "%s" sets both `paths` and `rename` (mutually exclusive)\n' "$cur_name" >&2
      exit 1
    fi
    if [ ${#cur_exclude[@]} -gt 0 ]; then
      printf 'error: opencode-import "%s" sets both `paths` and `exclude` (mutually exclusive)\n' "$cur_name" >&2
      exit 1
    fi
    local i
    for ((i = 0; i < ${#cur_path_src[@]}; i++)); do
      stage_one "$source/${cur_path_src[$i]}" "$stage/${cur_path_dest[$i]}" "$cur_name"
    done
    return 0
  fi

  # Auto mode: walk the standard layout.
  local sub entry rel dest
  for sub in commands skills agents plugins rules; do
    [ -d "$source/$sub" ] || continue
    for entry in "$source/$sub"/*; do
      [ -e "$entry" ] || continue
      rel="$sub/$(basename "$entry")"
      import_excluded "$rel" && continue
      dest=$(import_rename_for "$rel")
      stage_one "$entry" "$stage/$dest" "$cur_name"
    done
  done

  # Top-level opencode.*.json (excluding bare opencode.json) + package.json.
  for entry in "$source"/opencode.*.json "$source"/package.json; do
    [ -f "$entry" ] || continue
    rel="$(basename "$entry")"
    [ "$rel" = "opencode.json" ] && continue
    import_excluded "$rel" && continue
    dest=$(import_rename_for "$rel")
    stage_one "$entry" "$stage/$dest" "$cur_name"
  done

  # Rename entries pointing at non-standard sources (e.g.
  # mcp.fragment.json → opencode.foo.mcp.json) — anything referenced
  # by `rename` whose src wasn't auto-discovered.
  local i
  for ((i = 0; i < ${#cur_rename_src[@]}; i++)); do
    rel="${cur_rename_src[$i]}"
    dest="${cur_rename_dest[$i]}"
    [ -e "$stage/$dest" ] && continue
    [ -e "$source/$rel" ] || continue
    stage_one "$source/$rel" "$stage/$dest" "$cur_name"
  done
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

# Declarative Homebrew casks (Darwin only). The reconciler below makes
# the union of the listed Brewfiles authoritative for casks: missing
# casks are installed, extras are uninstalled. Formulae and taps are
# left alone — only casks are reconciled. We never invoke `brew` with
# sudo here so `setup.sh` stays passwordless.
#
# Two Brewfiles are reconciled on Darwin:
#   1. `$DOTFILES/config/Brewfile` — public, hand-edited base file.
#   2. `~/.config/dotfiles-managed/Brewfile.personal` — generated by
#      `home/personal.nix` from `dotfiles.personal.*` toggles. Absent
#      on work machines and on hosts with no personal cask selected;
#      Home Manager removes the symlink when the toggle flips off and
#      `scripts/brew-cleanup.sh --apply` then uninstalls the cask.
if [ "$(uname -s)" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
  # `Brewfile.personal` is generated by `home/personal.nix` via
  # `xdg.configFile`. This dotfiles config leaves Home Manager's
  # `xdg.configHome` at its default, so the generated file is expected
  # under `$HOME/.config`.
  for brewfile in \
    "$DOTFILES/config/Brewfile" \
    "$HOME/.config/dotfiles-managed/Brewfile.personal"; do
    if [ -f "$brewfile" ]; then
      printf '==> Reconciling Homebrew casks from %s\n' "$brewfile"
      # Work around Homebrew 5.1.9's cask API parser crashing on empty macOS requirements.
      HOMEBREW_NO_INSTALL_FROM_API=1 brew bundle install --no-upgrade --file="$brewfile"
    fi
  done

  # Uninstall any cask that is currently installed but absent from both
  # Brewfiles. This is what makes the Brewfile union the final state:
  # toggling `dotfiles.personal.<app>.enable` off (or removing a cask
  # from `config/Brewfile`) actually removes the cask on the next run.
  # Formulae and taps are out of scope; ad-hoc `brew install --formula`
  # and `brew tap` continue to work.
  "$DOTFILES/scripts/brew-cleanup.sh" --apply
fi
