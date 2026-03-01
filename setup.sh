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

# Private config — all under ~/.config/dotfiles/ (outside the git repo)
DOTFILES_CONFIG="$HOME/.config/dotfiles"
PRIVATE_TOML="$DOTFILES_CONFIG/private.toml"
PRIVATE_OPENCODE_JSON="$DOTFILES_CONFIG/private-opencode.json"
PRIVATE_SKILLS="$DOTFILES_CONFIG/private-skills"
PRIVATE_AGENTS_DIR="$DOTFILES_CONFIG/private-AGENTS"
PRIVATE_BUILD="$HOME/.local/share/dotfiles"

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
  local rel
  rel="${dest#"$HOME/"}"
  for skip in "${SKIP_LINKS[@]+"${SKIP_LINKS[@]}"}"; do
    case "$rel" in
      *"$skip") return 0 ;;
    esac
  done
  mkdir -p "$(dirname "$dest")"
  ln -snf "$src" "$dest"
}

# Merge public ($DOTFILES/config/opencode/skills) and private ($PRIVATE_SKILLS)
# skills into $PRIVATE_BUILD/opencode/skills, then symlink it as ~/.config/opencode/skills.
link_skills() {
  local merge_dir="$PRIVATE_BUILD/opencode/skills"
  local dest_link="$HOME/.config/opencode/skills"

  mkdir -p "$merge_dir"

  # Link public skills
  for skill_dir in "$DOTFILES/config/opencode/skills"/*/; do
    [[ -d "$skill_dir" ]] || continue
    local skill_name
    skill_name="$(basename "$skill_dir")"
    ln -snf "$skill_dir" "$merge_dir/$skill_name"
  done

  # Link private skills (if $PRIVATE_SKILLS exists)
  if [[ -d "$PRIVATE_SKILLS" ]]; then
    for skill_dir in "$PRIVATE_SKILLS"/*/; do
      [[ -d "$skill_dir" ]] || continue
      local skill_name
      skill_name="$(basename "$skill_dir")"
      ln -snf "$skill_dir" "$merge_dir/$skill_name"
    done
  fi

  mkdir -p "$(dirname "$dest_link")"
  ln -snf "$merge_dir" "$dest_link"
}

# Build merged opencode.json from public repo config and optional private overlay.
link_opencode_config() {
  local public_config="$DOTFILES/config/opencode/opencode.json"
  local merged_config="$PRIVATE_BUILD/opencode/opencode.json"
  local dest_link="$HOME/.config/opencode/opencode.json"

  mkdir -p "$(dirname "$merged_config")"

  if [[ -f "$PRIVATE_OPENCODE_JSON" ]]; then
    if ! command -v python3 >/dev/null 2>&1; then
      warn "python3 not found; ignoring private OpenCode overlay at $PRIVATE_OPENCODE_JSON"
      cp "$public_config" "$merged_config"
    else
      python3 - "$public_config" "$PRIVATE_OPENCODE_JSON" "$merged_config" <<'PY'
import json
import pathlib
import sys

public_path = pathlib.Path(sys.argv[1])
private_path = pathlib.Path(sys.argv[2])
out_path = pathlib.Path(sys.argv[3])

with public_path.open("r", encoding="utf-8") as f:
    public_cfg = json.load(f)

with private_path.open("r", encoding="utf-8") as f:
    private_cfg = json.load(f)

def deep_merge(base, overlay):
    if isinstance(base, dict) and isinstance(overlay, dict):
        result = dict(base)
        for key, value in overlay.items():
            result[key] = deep_merge(result[key], value) if key in result else value
        return result
    return overlay

merged = deep_merge(public_cfg, private_cfg)

with out_path.open("w", encoding="utf-8") as f:
    json.dump(merged, f, indent=2)
    f.write("\n")
PY
    fi
  else
    cp "$public_config" "$merged_config"
  fi

  mkdir -p "$(dirname "$dest_link")"
  ln -snf "$merged_config" "$dest_link"
}

# Build merged AGENTS.md from public repo file and optional private overlays.
link_agents() {
  local merged_agents="$PRIVATE_BUILD/opencode/AGENTS.md"
  local dest_link="$HOME/.config/opencode/AGENTS.md"
  local agents_file
  local -a agents_files=()

  mkdir -p "$(dirname "$merged_agents")"
  cp "$DOTFILES/config/opencode/AGENTS.md" "$merged_agents"

  # Multi-file overlay directory.
  if [[ -d "$PRIVATE_AGENTS_DIR" ]]; then
    shopt -s nullglob
    agents_files=("$PRIVATE_AGENTS_DIR"/*)
    shopt -u nullglob

    while IFS= read -r agents_file; do
      [[ -f "$agents_file" ]] || continue
      if [[ ! -r "$agents_file" ]]; then
        warn "private AGENTS overlay is not readable: $agents_file"
        continue
      fi
      [[ -s "$agents_file" ]] || continue

      printf '\n\n# Private AGENTS overlay: %s\n\n' "$(basename "$agents_file")" >> "$merged_agents"
      cat "$agents_file" >> "$merged_agents"
    done < <(printf '%s\n' "${agents_files[@]}" | LC_ALL=C sort)
  fi

  mkdir -p "$(dirname "$dest_link")"
  ln -snf "$merged_agents" "$dest_link"
}

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

log "Recording dotfiles path"
mkdir -p "$DOTFILES_CONFIG"
printf '%s\n' "$DOTFILES" > "$DOTFILES_CONFIG/path"

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
link_opencode_config
link_agents
link_skills

log "Ensuring workspace directories"
mkdir -p "$DEV_ROOT/repos" "$DEV_ROOT/wt" "$DEV_ROOT/detached"

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
fi
if [[ ! -d "$PRIVATE_SKILLS" ]]; then
  printf 'tip: place private opencode skills under %s/<skill-name>/SKILL.md\n' "$PRIVATE_SKILLS"
fi
if [[ ! -d "$PRIVATE_AGENTS_DIR" ]]; then
  printf 'tip: place private opencode AGENTS overlays under %s/<name>.md\n' "$PRIVATE_AGENTS_DIR"
fi
if [[ ! -f "$PRIVATE_OPENCODE_JSON" ]]; then
  printf 'tip: place private opencode config at %s to override opencode.json (eg. MCP servers)\n' "$PRIVATE_OPENCODE_JSON"
fi

log "Done"
printf 'Next steps:\n'
printf '  1) Restart your shell\n'
printf '  2) Run opencode and /connect once\n'
printf '  3) Run task doctor\n'
