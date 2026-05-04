# Dotfiles

This repo manages shell, editor, terminal, window manager, SSH, task, and OpenCode config from one place via [Home Manager](https://nix-community.github.io/home-manager/).

## Quick start

Prerequisite: install [Nix](https://nixos.org).

```bash
mkdir -p ~/.config/dotfiles
cp dotfiles.example.toml ~/.config/dotfiles/config.toml
$EDITOR ~/.config/dotfiles/config.toml
./setup.sh
```

For a minimal first run, `config.toml` is optional. You can run `./setup.sh` first and fill private values in later.

After setup:

- restart your shell
- run `task doctor`
- if you use OpenCode, run it once and connect any MCP servers you have configured

To preview the generated output without activating it:

```bash
nix --extra-experimental-features 'nix-command flakes' \
  build --impure --dry-run \
  "path:.#homeConfigurations.thomas-darwin.activationPackage"
```

## What setup does

`setup.sh` is a 46-line shell shim that:

1. Resolves the host attribute — `thomas-darwin` on macOS, `thomas-linux` on Linux. `DOTFILES_HOST` overrides.
2. Builds `homeConfigurations.<host>.activationPackage` from this flake.
3. Runs the resulting `activate` script.

The activation flow is pure Home Manager. Activation blocks under `home/bootstrap.nix`:

- record the repo path at `~/.config/dotfiles/path`
- clean up legacy Rust-managed symlinks (idempotent on a fresh machine)
- run `task bootstrap` so workspace dirs and asdf node are ready

Re-running `./setup.sh` is normal — it is idempotent. Home Manager keeps generations; roll back with `home-manager switch --rollback`.

## What to edit where

- shared config: edit files in this repo
- per-host wiring: edit `home/hosts/<host>.nix` (rules mode, identity overrides, etc.)
- private machine-specific config: put it under `~/.config/dotfiles/`

After changing anything under `~/.config/dotfiles/`, refresh the private flake input:

```bash
nix --extra-experimental-features 'nix-command flakes' \
  flake update private --flake .
./setup.sh
```

Common private files:

- `~/.config/dotfiles/config.toml`: git identity, goto API URL
- `~/.config/dotfiles/ssh/config`: private SSH hosts and `IdentityFile` paths
- `~/.config/dotfiles/goto/database.yml`: private goto bookmarks
- `~/.config/dotfiles/opencode/`: private OpenCode overlays
- `~/.config/dotfiles/task.<name>.toml`: private task overlays
- `~/.config/dotfiles/cargo.<name>.toml`: private cargo overlays
- `~/.config/dotfiles/aerospace.<name>.toml`: private AeroSpace rules

## Repo scope

This repo currently manages config for things like:

- shell startup files: `bash`, `fish`, `tmux`, `zsh`
- editors and terminals: `helix`, `kitty`, `alacritty`
- Linux desktop config: `hypr`, `mako`, `rofi`, `waybar`
- developer tooling: `cargo`, `task`, `goto`, `ssh`, `yazi`
- OpenCode config, commands, skills, agents, and plugins
- macOS LaunchAgents

Linux-only modules are gated with `lib.mkIf pkgs.stdenv.isLinux`, so importing this flake on macOS leaves them as no-ops without explicit skip lists.

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

The HM module deep-merges `opencode.json`, merges commands/skills/agents/plugins, and links the result into `~/.config/opencode/`. Set `programs.opencode.rulesMode` in `home/hosts/<host>.nix` to choose how `AGENTS.md` is built (`merged`, `private_only`, or `disabled`).

If you change plugins or plugin dependencies, install dependencies with:

```bash
bun install --cwd ~/.config/opencode
```
