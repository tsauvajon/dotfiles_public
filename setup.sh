#!/usr/bin/env bash
# To enable private setup (git identity, network config):
#
#   cp private.toml.example ~/.config/dotfiles/private.toml
#   $EDITOR ~/.config/dotfiles/private.toml
#   bash setup.sh
#
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"
DEV_ROOT="${DEV_ROOT:-$HOME/dev}"

# Private config
PRIVATE_TOML="${DOTFILES_PRIVATE_TOML:-$HOME/.config/dotfiles/private.toml}"

# Read a scalar from private.toml: private_get '.git.name'
private_get() {
  nix run nixpkgs#dasel -- -f "$PRIVATE_TOML" -r toml "$1" 2>/dev/null | tr -d "'"
}

# Read a list from private.toml, one entry per line: private_list '.dotfiles.skip_links'
private_list() {
  nix run nixpkgs#dasel -- -f "$PRIVATE_TOML" -r toml "${1}.all()" 2>/dev/null | tr -d "'"
}

# Populate skip list early so link() can use it
SKIP_LINKS=()
if [[ -f "$PRIVATE_TOML" ]]; then
  while IFS= read -r entry; do
    [[ -n "$entry" ]] && SKIP_LINKS+=("$entry")
  done < <(private_list '.dotfiles.skip_links')
fi

link() {
  local src="$1"
  local dest="$2"
  local base
  base="$(basename "$dest")"
  for skip in "${SKIP_LINKS[@]+"${SKIP_LINKS[@]}"}"; do
    case "$base" in
      $skip) return 0 ;;
    esac
  done
  mkdir -p "$(dirname "$dest")"
  ln -snf "$src" "$dest"
}

# Merge public and private skills into a single directory, then symlink it.
# Usage: link_skills <public-skills-src> <merge-dir> <dest-link>
#
# Any subdirectory found in <public-skills-src> or in
# ~/.config/dotfiles/private-skills/ is symlinked into <merge-dir>.
# <dest-link> is then symlinked to <merge-dir>.
link_skills() {
  local public_src="$1"
  local merge_dir="$2"
  local dest_link="$3"
  local private_src="$HOME/.config/dotfiles/private-skills"

  mkdir -p "$merge_dir"

  # Link public skills
  if [[ -d "$public_src" ]]; then
    for skill_dir in "$public_src"/*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name
      skill_name="$(basename "$skill_dir")"
      ln -snf "$skill_dir" "$merge_dir/$skill_name"
    done
  fi

  # Link private skills (if the private-skills directory exists)
  if [[ -d "$private_src" ]]; then
    for skill_dir in "$private_src"/*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name
      skill_name="$(basename "$skill_dir")"
      ln -snf "$skill_dir" "$merge_dir/$skill_name"
    done
  fi

  # Point the live config location at the merged directory
  mkdir -p "$(dirname "$dest_link")"
  ln -snf "$merge_dir" "$dest_link"
}

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

log "Recording dotfiles path"
mkdir -p "$HOME/.config/dotfiles"
printf '%s\n' "$DOTFILES" > "$HOME/.config/dotfiles/path"

log "Linking home files"
link "$DOTFILES/home/tmux.conf" "$HOME/.tmux.conf"
link "$DOTFILES/home/profile" "$HOME/.profile"
link "$DOTFILES/home/fish_profile" "$HOME/.fish_profile"
link "$DOTFILES/home/bashrc" "$HOME/.bashrc"
link "$DOTFILES/home/bash_profile" "$HOME/.bash_profile"
link "$DOTFILES/home/nix-channels" "$HOME/.nix-channels"
link "$DOTFILES/home/tool-versions" "$HOME/.tool-versions"
link "$DOTFILES/home/flakes/" "$HOME/flakes"
link "$DOTFILES/home/tmux/" "$HOME/.tmux"

log "Linking config files"
link "$DOTFILES/config/wayland-env.sh" "$HOME/.config/wayland-env.sh"
link "$DOTFILES/config/espflash" "$HOME/.config/espflash"
link "$DOTFILES/config/fish" "$HOME/.config/fish"
link "$DOTFILES/config/hypr" "$HOME/.config/hypr"
link "$DOTFILES/config/mako" "$HOME/.config/mako"
link "$DOTFILES/config/rofi" "$HOME/.config/rofi"
link "$DOTFILES/config/kitty" "$HOME/.config/kitty"
link "$DOTFILES/config/waybar" "$HOME/.config/waybar"
link "$DOTFILES/config/opencode/opencode.json" "$HOME/.config/opencode/opencode.json"
link "$DOTFILES/config/opencode/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
link_skills "$DOTFILES/config/opencode/skills" "$HOME/.local/share/dotfiles/opencode/skills" "$HOME/.config/opencode/skills"

log "Ensuring workspace directories"
mkdir -p "$DEV_ROOT/repos" "$DEV_ROOT/wt"

if command -v nix >/dev/null 2>&1; then
  local_flake_ref="path:${DOTFILES}/home/flakes#toolchain"
  log "Installing Nix toolchain from ${DOTFILES}/home/flakes"
  nix --extra-experimental-features "nix-command flakes" profile remove toolchain >/dev/null 2>&1 || true
  nix --extra-experimental-features "nix-command flakes" profile add "$local_flake_ref"

  if [[ -d "$HOME/.nix-profile/bin" ]] && [[ ":$PATH:" != *":$HOME/.nix-profile/bin:"* ]]; then
    export PATH="$HOME/.nix-profile/bin:$PATH"
  fi
else
  warn "nix not found. Install Nix first to use the flake toolchain."
fi

if [[ -x "$HOME/.cargo/bin/task" ]]; then
  log "Running task bootstrap"
  "$HOME/.cargo/bin/task" bootstrap || warn "task bootstrap requires an interactive terminal — run it manually"
else
  warn "task not found"
fi

# Private setup
PRIVATE_BUILD="$HOME/.local/share/dotfiles"

if [[ -f "$PRIVATE_TOML" ]]; then
  log "Loading private config from $PRIVATE_TOML"

  missing=()
  for key in '.git.name' '.git.email' '.git.signing_key' '.goto.api_url' '.vscodium.trusted_roots'; do
    [[ -z "$(private_get "$key")" ]] && missing+=("$key")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "private setup skipped — missing keys in $PRIVATE_TOML: ${missing[*]}"
  else
    log "Building private files"
    mkdir -p "$PRIVATE_BUILD/goto" "$PRIVATE_BUILD/task"

    GIT_NAME="$(private_get '.git.name')"
    GIT_EMAIL="$(private_get '.git.email')"
    GIT_SIGNINGKEY="$(private_get '.git.signing_key')"
    GOTO_API_URL="$(private_get '.goto.api_url')"

    sed \
      -e "s/YOUR_NAME/$GIT_NAME/" \
      -e "s/YOUR_EMAIL/$GIT_EMAIL/" \
      -e "s/YOUR_GPG_KEY_ID/$GIT_SIGNINGKEY/" \
      "$DOTFILES/home/gitconfig" > "$PRIVATE_BUILD/gitconfig"

    sed \
      -e "s|YOUR_GOTO_CONFIG_API_URL|$GOTO_API_URL|" \
      "$DOTFILES/config/goto/config.yml" > "$PRIVATE_BUILD/goto/config.yml"

    {
      cat "$DOTFILES/config/task/config.toml"
      printf '\n[vscodium]\ntrusted_roots = [\n'
      while IFS= read -r root; do
        [[ -n "$root" ]] && printf '    "%s",\n' "$root"
      done < <(private_list '.vscodium.trusted_roots')
      printf ']\n'
    } > "$PRIVATE_BUILD/task/config.toml"

    log "Symlinking private files"
    link "$PRIVATE_BUILD/gitconfig"            "$HOME/.gitconfig"
    link "$PRIVATE_BUILD/goto/config.yml"      "$HOME/.config/goto/config.yml"
    link "$PRIVATE_BUILD/task/config.toml"     "$HOME/.config/task/config.toml"
  fi
else
  printf 'tip: place private.toml at %s to configure git identity and network URLs\n' "$PRIVATE_TOML"
  printf 'tip: place private opencode skills under ~/.config/dotfiles/private-skills/<skill-name>/SKILL.md\n'
fi

log "Done"
printf 'Next steps:\n'
printf '  1) Restart your shell\n'
printf '  2) Run opencode and /connect once\n'
printf '  3) Run task doctor\n'
