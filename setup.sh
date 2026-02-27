#!/usr/bin/env bash
# To enable private setup (git identity, network config):
#
#   cp private.env.example ~/.config/dotfiles/private.env
#   $EDITOR ~/.config/dotfiles/private.env
#   bash setup.sh
#
set -euo pipefail

DOTFILES="${DOTFILES:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)}"
DEV_ROOT="${DEV_ROOT:-$HOME/dev}"

link() {
  local src="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  ln -snf "$src" "$dest"
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
link "$DOTFILES/home/task.bash-completion" "$HOME/task.bash-completion"
link "$DOTFILES/home/nix-channels" "$HOME/.nix-channels"
link "$DOTFILES/home/tool-versions" "$HOME/.tool-versions"

link "$DOTFILES/home/flakes/" "$HOME/flakes"
link "$DOTFILES/home/tmux/" "$HOME/.tmux"
mkdir -p "$HOME/.local/bin"
link "$DOTFILES/home/bin/task" "$HOME/.local/bin/task"
link "$DOTFILES/home/bin/wt" "$HOME/.local/bin/wt"
link "$DOTFILES/home/bin/oc-codex" "$HOME/.local/bin/oc-codex"
link "$DOTFILES/home/bin/oc-claude" "$HOME/.local/bin/oc-claude"

log "Linking config files"
link "$DOTFILES/config/wayland-env.sh" "$HOME/.config/wayland-env.sh"
link "$DOTFILES/config/espflash" "$HOME/.config/espflash"
link "$DOTFILES/config/fish" "$HOME/.config/fish"
link "$DOTFILES/config/hypr" "$HOME/.config/hypr"
link "$DOTFILES/config/mako" "$HOME/.config/mako"
link "$DOTFILES/config/rofi" "$HOME/.config/rofi"
link "$DOTFILES/config/task" "$HOME/.config/task"
link "$DOTFILES/config/kitty" "$HOME/.config/kitty"
link "$DOTFILES/config/waybar" "$HOME/.config/waybar"
link "$DOTFILES/config/opencode/opencode.json" "$HOME/.config/opencode/opencode.json"
link "$DOTFILES/config/opencode/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
link "$DOTFILES/config/opencode/skills" "$HOME/.config/opencode/skills"

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

if [[ -x "$HOME/.local/bin/task" ]]; then
  log "Running task bootstrap"
  "$HOME/.local/bin/task" bootstrap
else
  warn "task script not executable yet; skipping bootstrap."
fi

# Private setup
PRIVATE_ENV="${DOTFILES_PRIVATE_ENV:-$HOME/.config/dotfiles/private.env}"
PRIVATE_BUILD="$HOME/.local/share/dotfiles"

if [[ -f "$PRIVATE_ENV" ]]; then
  log "Loading private env from $PRIVATE_ENV"
  # shellcheck source=/dev/null
  source "$PRIVATE_ENV"

  missing=()
  for var in GIT_NAME GIT_EMAIL GIT_SIGNINGKEY GOTO_CONFIG_API_URL; do
    [[ -z "${!var:-}" ]] && missing+=("$var")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "private setup skipped — missing variables in $PRIVATE_ENV: ${missing[*]}"
  else
    log "Building private files"
    mkdir -p "$PRIVATE_BUILD/goto"

    sed \
      -e "s/YOUR_NAME/$GIT_NAME/" \
      -e "s/YOUR_EMAIL/$GIT_EMAIL/" \
      -e "s/YOUR_GPG_KEY_ID/$GIT_SIGNINGKEY/" \
      "$DOTFILES/home/gitconfig" > "$PRIVATE_BUILD/gitconfig"

    sed \
      -e "s|YOUR_GOTO_CONFIG_API_URL|$GOTO_CONFIG_API_URL|" \
      "$DOTFILES/config/goto/config.yml" > "$PRIVATE_BUILD/goto/config.yml"

    log "Symlinking private files"
    link "$PRIVATE_BUILD/gitconfig"       "$HOME/.gitconfig"
    link "$PRIVATE_BUILD/goto/config.yml" "$HOME/.config/goto/config.yml"
  fi
else
  printf 'tip: place private.env at %s to configure git identity and network URLs\n' "$PRIVATE_ENV"
fi

log "Done"
printf 'Next steps:\n'
printf '  1) Restart your shell\n'
printf '  2) Run opencode and /connect once\n'
printf '  3) Run task doctor\n'
