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

# Populate skip list early so all link_* helpers can use it
SKIP_LINKS=()
if [[ -f "$PRIVATE_TOML" ]]; then
  while IFS= read -r entry; do
    [[ -n "$entry" ]] && SKIP_LINKS+=("$entry")
  done < <(private_list '.dotfiles.skip_links')
fi

log()  { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

AGENTS_MODE="merged"
if [[ -f "$PRIVATE_TOML" ]]; then
  case "$(private_get '.dotfiles.agents_mode')" in
    ""|merged)
      AGENTS_MODE="merged"
      ;;
    private_only)
      AGENTS_MODE="private_only"
      ;;
    disabled)
      AGENTS_MODE="disabled"
      ;;
    *)
      warn "unknown .dotfiles.agents_mode value in $PRIVATE_TOML, using 'merged'"
      AGENTS_MODE="merged"
      ;;
  esac
fi

normalize_skip_path() {
  local path="$1"
  path="${path#"$HOME/"}"
  path="${path#\~/}"
  path="${path#./}"
  printf '%s' "$path"
}

SKIP_NORMS=()
for _skip in "${SKIP_LINKS[@]+"${SKIP_LINKS[@]}"}"; do
  SKIP_NORMS+=("$(normalize_skip_path "$_skip")")
done

remove_managed_link_if_present() {
  local dest="$1"
  local target

  if [[ -L "$dest" ]]; then
    target="$(readlink "$dest")"

    case "$target" in
      "$DOTFILES"/*|"$PRIVATE_BUILD"/*)
        rm "$dest"
        ;;
    esac
    return 0
  fi

  # Best-effort cleanup for stale generated placeholders.
  if [[ -f "$dest" && ! -s "$dest" ]]; then
    rm "$dest"
  fi
}

should_skip_dest() {
  local dest="$1"
  local dest_norm
  dest_norm="$(normalize_skip_path "$dest")"

  local i
  for i in "${!SKIP_NORMS[@]}"; do
    [[ -n "${SKIP_NORMS[$i]}" ]] || continue
    case "$dest_norm" in
      *"${SKIP_NORMS[$i]}") return 0 ;;
    esac
  done
  return 1
}

link() {
  local src="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  ln -snf "$src" "$dest"
}

escape_sed_replacement() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

managed_link() {
  local src="$1"
  local dest="$2"
  if should_skip_dest "$dest"; then
    log "Skipping $dest"
    remove_managed_link_if_present "$dest"
    return 0
  fi
  link "$src" "$dest"
}

# Merge public ($DOTFILES/config/opencode/skills) and private ($PRIVATE_SKILLS)
# skills into $PRIVATE_BUILD/opencode/skills, then symlink it as ~/.config/opencode/skills.
link_skills() {
  local merge_dir="$PRIVATE_BUILD/opencode/skills"
  local dest_link="$HOME/.config/opencode/skills"

  if should_skip_dest "$dest_link"; then
    log "Skipping $dest_link"
    remove_managed_link_if_present "$dest_link"
    return 0
  fi

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

  link "$merge_dir" "$dest_link"
}

# Build merged opencode.json from public repo config and optional private overlay.
link_opencode_config() {
  local public_config="$DOTFILES/config/opencode/opencode.json"
  local merged_config="$PRIVATE_BUILD/opencode/opencode.json"
  local dest_link="$HOME/.config/opencode/opencode.json"

  if should_skip_dest "$dest_link"; then
    log "Skipping $dest_link"
    remove_managed_link_if_present "$dest_link"
    return 0
  fi

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

  link "$merged_config" "$dest_link"
}

# Build merged AGENTS.md from public repo file and optional private overlays.
link_agents() {
  local merged_agents="$PRIVATE_BUILD/opencode/AGENTS.md"
  local dest_link="$HOME/.config/opencode/AGENTS.md"
  local escaped_dotfiles
  local agents_file
  local appended_any=0
  local -a agents_files=()

  if should_skip_dest "$dest_link" || [[ "$AGENTS_MODE" == "disabled" ]]; then
    [[ "$AGENTS_MODE" == "disabled" ]] || log "Skipping $dest_link"
    remove_managed_link_if_present "$dest_link"
    return 0
  fi

  mkdir -p "$(dirname "$merged_agents")"

  if [[ "$AGENTS_MODE" == "merged" ]]; then
    cp "$DOTFILES/config/opencode/AGENTS.md" "$merged_agents"
  else
    : > "$merged_agents"
  fi

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

      if [[ -s "$merged_agents" ]]; then
        printf '\n\n' >> "$merged_agents"
      fi
      printf '# Private AGENTS overlay: %s\n\n' "$(basename "$agents_file")" >> "$merged_agents"
      cat "$agents_file" >> "$merged_agents"
      appended_any=1
    done < <(printf '%s\n' "${agents_files[@]}" | LC_ALL=C sort)
  fi

  if [[ "$AGENTS_MODE" == "private_only" && "$appended_any" -eq 0 ]]; then
    warn "agents_mode=private_only but no readable non-empty files found in $PRIVATE_AGENTS_DIR"
  fi

  escaped_dotfiles="$(escape_sed_replacement "$DOTFILES")"
  sed -i.bak "s|__DOTFILES_PATH__|$escaped_dotfiles|g" "$merged_agents"
  rm -f "$merged_agents.bak"

  link "$merged_agents" "$dest_link"
}

# Merge public AeroSpace config with private overlays (aerospace.*.toml).
link_aerospace() {
  local base="$DOTFILES/home/aerospace.toml"
  local merged="$PRIVATE_BUILD/aerospace.toml"
  local dest_link="$HOME/.aerospace.toml"

  if should_skip_dest "$dest_link"; then
    log "Skipping $dest_link"
    remove_managed_link_if_present "$dest_link"
    return 0
  fi

  if [[ ! -f "$base" ]]; then
    warn "aerospace base config not found at $base"
    return 0
  fi

  mkdir -p "$(dirname "$merged")"
  cp "$base" "$merged"

  # Append private overlays in sorted order
  shopt -s nullglob
  local -a overlays=("$DOTFILES_CONFIG"/aerospace.*.toml)
  shopt -u nullglob

  for overlay in "${overlays[@]}"; do
    [[ -f "$overlay" && -r "$overlay" && -s "$overlay" ]] || continue
    printf '\n' >> "$merged"
    cat "$overlay" >> "$merged"
  done

  link "$merged" "$dest_link"
}

# Merge public Cargo config with private overlays (cargo.*.toml).
link_cargo() {
  local base="$DOTFILES/home/cargo-config.toml"
  local merged="$PRIVATE_BUILD/cargo-config.toml"
  local dest_link="$HOME/.cargo/config.toml"

  if should_skip_dest "$dest_link"; then
    log "Skipping $dest_link"
    remove_managed_link_if_present "$dest_link"
    return 0
  fi

  if [[ ! -f "$base" ]]; then
    warn "cargo base config not found at $base"
    return 0
  fi

  mkdir -p "$(dirname "$merged")" "$(dirname "$dest_link")"
  cp "$base" "$merged"

  # Append private overlays in sorted order
  shopt -s nullglob
  local -a overlays=("$DOTFILES_CONFIG"/cargo.*.toml)
  shopt -u nullglob

  for overlay in "${overlays[@]}"; do
    [[ -f "$overlay" && -r "$overlay" && -s "$overlay" ]] || continue
    printf '\n' >> "$merged"
    cat "$overlay" >> "$merged"
  done

  link "$merged" "$dest_link"
}

# Merge public Alacritty config with private overlays (alacritty.*.toml).
link_alacritty() {
  local base="$DOTFILES/config/alacritty/alacritty.toml"
  local merged="$PRIVATE_BUILD/alacritty.toml"
  local dest_link="$HOME/.config/alacritty/alacritty.toml"

  if should_skip_dest "$dest_link"; then
    log "Skipping $dest_link"
    remove_managed_link_if_present "$dest_link"
    return 0
  fi

  if [[ ! -f "$base" ]]; then
    warn "alacritty base config not found at $base"
    return 0
  fi

  mkdir -p "$(dirname "$merged")" "$(dirname "$dest_link")"
  cp "$base" "$merged"

  # Append private overlays in sorted order
  shopt -s nullglob
  local -a overlays=("$DOTFILES_CONFIG"/alacritty.*.toml)
  shopt -u nullglob

  if [[ ${#overlays[@]} -gt 0 ]]; then
    while IFS= read -r overlay; do
      [[ -f "$overlay" && -r "$overlay" && -s "$overlay" ]] || continue
      printf '\n' >> "$merged"
      cat "$overlay" >> "$merged"
    done < <(printf '%s\n' "${overlays[@]}" | LC_ALL=C sort)
  fi

  link "$merged" "$dest_link"

  # Link themes submodule so the import path resolves
  local themes_src="$DOTFILES/config/alacritty/themes"
  local themes_dest="$HOME/.config/alacritty/themes"
  if [[ -d "$themes_src" ]]; then
    ln -snf "$themes_src" "$themes_dest"
  fi
}

log "Recording dotfiles path"
mkdir -p "$DOTFILES_CONFIG"
printf '%s\n' "$DOTFILES" > "$DOTFILES_CONFIG/path"

log "Linking home files"
managed_link "$DOTFILES/home/tmux.conf" "$HOME/.tmux.conf"
managed_link "$DOTFILES/home/profile" "$HOME/.profile"
managed_link "$DOTFILES/home/fish_profile" "$HOME/.fish_profile"
managed_link "$DOTFILES/home/bashrc" "$HOME/.bashrc"
managed_link "$DOTFILES/home/bash_profile" "$HOME/.bash_profile"
managed_link "$DOTFILES/home/nix-channels" "$HOME/.nix-channels"
managed_link "$DOTFILES/home/tool-versions" "$HOME/.tool-versions"
managed_link "$DOTFILES/home/flakes/" "$HOME/flakes"
managed_link "$DOTFILES/home/tmux/" "$HOME/.tmux"

log "Linking config files"
managed_link "$DOTFILES/config/wayland-env.sh" "$HOME/.config/wayland-env.sh"
managed_link "$DOTFILES/config/espflash" "$HOME/.config/espflash"
managed_link "$DOTFILES/config/fish" "$HOME/.config/fish"
managed_link "$DOTFILES/config/hypr" "$HOME/.config/hypr"
managed_link "$DOTFILES/config/mako" "$HOME/.config/mako"
managed_link "$DOTFILES/config/rofi" "$HOME/.config/rofi"
managed_link "$DOTFILES/config/kitty" "$HOME/.config/kitty"
managed_link "$DOTFILES/config/waybar" "$HOME/.config/waybar"
link_opencode_config
link_agents
link_skills
link_aerospace
link_cargo
link_alacritty

log "Ensuring workspace directories"
mkdir -p "$DEV_ROOT/repos" "$DEV_ROOT/wt" "$DEV_ROOT/detached"

if command -v nix >/dev/null 2>&1; then
  local_flake_ref="path:${DOTFILES}/home/flakes/toolchain#toolchain"
  log "Installing Nix toolchain from ${DOTFILES}/home/flakes/toolchain"
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
  "$HOME/.cargo/bin/task" bootstrap --yes || warn "task bootstrap failed"
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
    managed_link "$PRIVATE_BUILD/gitconfig" "$HOME/.gitconfig"
    managed_link "$PRIVATE_BUILD/goto/config.yml" "$HOME/.config/goto/config.yml"
    managed_link "$PRIVATE_BUILD/task/config.toml" "$HOME/.config/task/config.toml"
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
