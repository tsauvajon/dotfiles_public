# Dotfiles

This repo manages shell, editor, terminal, window manager, SSH, task, and OpenCode config from one place.

## Quick start

Prerequisite: install either `nix` or `cargo`.

```bash
mkdir -p ~/.config/dotfiles
cp config.toml.example ~/.config/dotfiles/config.toml
$EDITOR ~/.config/dotfiles/config.toml
./setup.sh
```

For a minimal first run, `config.toml` is optional. You can run `./setup.sh` first and fill private values in later.

After setup:

- restart your shell
- run `task doctor`
- if you use OpenCode, run it once and connect any MCP servers you have configured

To verify the generated output without changing anything:

```bash
./setup.sh --check
```

## What setup does

`setup.sh` is a thin wrapper around the Rust setup tool in this repo. It uses `nix run` when `nix` is available, otherwise it falls back to `cargo run`.

On each run it:

- records the repo path at `~/.config/dotfiles/path`
- symlinks files from `config/` into the matching `$HOME` and `~/.config/` paths
- generates merged config under `~/.local/share/dotfiles/` and links that into place
- creates workspace directories under `~/dev/{repos,wt,detached}` unless `DEV_ROOT` is set
- installs Nix profiles for the general toolchain, Helix language tooling, and Steel-enabled Helix plugins when `nix` is available
- runs `task bootstrap` when the `task` binary is installed

The setup is intended to be idempotent, so re-running `./setup.sh` is normal.

## What to edit where

- shared config: edit files in this repo
- private machine-specific config: put it under `~/.config/dotfiles/`
- generated output: do not edit `~/.local/share/dotfiles/` directly

Common private files:

- `~/.config/dotfiles/config.toml`: git identity, goto API URL, skip lists, rules mode
- `~/.config/dotfiles/ssh/config`: private SSH hosts and `IdentityFile` paths
- `~/.config/dotfiles/goto/database.yml`: private goto bookmarks
- `~/.config/dotfiles/opencode/`: private OpenCode overlays

## Generated and merged files

Most entries are direct symlinks to files in this repo, so edits take effect immediately.

Some outputs are generated or merged first, then linked into place:

- `~/.gitconfig` from `config/git/gitconfig` plus private values from `config.toml`
- `~/.config/goto/config.yml` from `config/goto/config.yml` plus private values from `config.toml`
- `~/.config/task/config.toml` from `config/task/config.toml` plus repo and private overlays
- `~/.config/opencode/*` from repo and private overlays
- platform overlay configs such as Cargo, Alacritty, and AeroSpace

Never edit the generated copies directly. Update the source file in this repo or the matching file under `~/.config/dotfiles/`, then re-run `./setup.sh`.

## Private config

Start with:

```bash
cp config.toml.example ~/.config/dotfiles/config.toml
```

Important fields in `config.toml`:

- `[git]`: name, email, signing key
- `[goto]`: `api_url`
- `[dotfiles].skip_destinations`: skip specific outputs relative to `$HOME`
- `[dotfiles].skip_sources`: skip specific repo sources before merge/link
- `[dotfiles].rules_mode`: control whether `~/.config/opencode/AGENTS.md` is merged, private-only, or disabled

Private SSH entries belong in `~/.config/dotfiles/ssh/config`. The repo-managed `~/.ssh/config` includes that file first.

## Repo scope

This repo currently manages config for things like:

- shell startup files: `bash`, `fish`, `tmux`
- editors and terminals: `helix`, `kitty`, `alacritty`
- Linux desktop config: `hypr`, `mako`, `rofi`, `waybar`
- developer tooling: `cargo`, `task`, `goto`, `ssh`
- OpenCode config, commands, skills, agents, and plugins

## Optional OpenCode customization

OpenCode is supported here, but it is optional.

Public config lives in `config/opencode/`. Private machine-local overrides live in `~/.config/dotfiles/opencode/`.

Useful private paths:

- `~/.config/dotfiles/opencode/opencode.json`: main private override
- `~/.config/dotfiles/opencode/opencode.*.json`: additional JSON fragments
- `~/.config/dotfiles/opencode/rules/`: AGENTS/rules overlays
- `~/.config/dotfiles/opencode/commands/`: private slash commands
- `~/.config/dotfiles/opencode/skills/`: private skills
- `~/.config/dotfiles/opencode/agents/`: private agents
- `~/.config/dotfiles/opencode/plugins/`: private plugins
- `~/.config/dotfiles/opencode/package.json`: private plugin dependency overlay

`./setup.sh` deep-merges `opencode.json`, merges commands/skills/agents/plugins, and links the result into `~/.config/opencode/`.

If you change plugins or plugin dependencies, install dependencies with:

```bash
bun install --cwd ~/.config/opencode
```
