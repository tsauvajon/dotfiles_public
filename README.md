# Dotfiles

Shell, editor, terminal, window manager, SSH, task, and OpenCode config managed
from one place via [Home Manager](https://nix-community.github.io/home-manager/).

## Quick start

Prerequisite: install [Nix](https://nixos.org).

```bash
mkdir -p ~/.config/dotfiles
cp dotfiles.example.toml ~/.config/dotfiles/config.toml
$EDITOR ~/.config/dotfiles/config.toml
./setup.sh
```

`config.toml` is optional for a minimal first run. You can run `./setup.sh`
first and fill private values in later.

After setup:

- restart your shell
- run `task doctor`
- if you use OpenCode, run it once and connect any MCP servers you have
  configured

To preview the generated output without activating it:

```bash
nix --extra-experimental-features 'nix-command flakes' \
  build --impure --dry-run \
  "path:.#homeConfigurations.thomas-darwin.activationPackage"
```

## What setup does

`setup.sh` is a thin shell shim:

1. Resolves the host attribute — `thomas-darwin` on macOS, `thomas-linux` on
   Linux. `DOTFILES_HOST` overrides.
2. Builds `homeConfigurations.<host>.activationPackage` from this flake.
3. Runs the resulting `activate` script.

The activation flow is pure Home Manager. Activation blocks under
`home/bootstrap.nix` record the repo path at `~/.config/dotfiles/path`, clean
up any legacy symlinks left over from the old Rust-based setup tool, and run
`task bootstrap` so workspace dirs are ready.

Re-running `./setup.sh` is idempotent. Home Manager keeps generations; roll
back with `home-manager switch --rollback`.

## What to edit where

- shared config: edit files under `config/<tool>/` or `home/<module>.nix`
- per-host wiring: edit `home/hosts/<host>.nix` (rules mode, identity
  overrides, etc.)
- private machine-specific config: put it under `~/.config/dotfiles/`

After changing anything under `~/.config/dotfiles/`, just rerun `./setup.sh`.
The build uses `--override-input private "path:$HOME/.config/dotfiles"` so
Home Manager reads the working tree directly with no flake.lock update needed:

```bash
./setup.sh
```

Common private files:

- `~/.config/dotfiles/config.toml` — git identity, goto API URL
- `~/.config/dotfiles/extra.gitconfig` — extra gitconfig included from
  `~/.config/git/config`
- `~/.config/dotfiles/ssh/config` — private SSH hosts and `IdentityFile` paths
- `~/.config/dotfiles/goto/database.yml` — private goto bookmarks
- `~/.config/dotfiles/opencode/` — private OpenCode overlays (see below)
- `~/.config/dotfiles/task.<name>.toml` — private task overlays
- `~/.config/dotfiles/cargo.<name>.toml` — private cargo overlays
- `~/.config/dotfiles/aerospace.<name>.toml` — private AeroSpace rules

## Repo scope

Currently managed:

- shell startup files: `bash`, `fish`, `tmux`, `zsh`
- editors and terminals: `helix`, `kitty`, `alacritty`
- Linux desktop session: `hypr`, `mako`, `rofi`, `waybar`
- developer tooling: `cargo`, `task`, `goto`, `ssh`, `yazi`
- JavaScript tooling: `bun` globally; use project-local Nix for Node.js when needed
- OpenCode config, commands, skills, agents, and plugins
- macOS LaunchAgents (`Library/LaunchAgents/*.plist`)

See [`docs/nodejs.md`](docs/nodejs.md) for the Bun-first JavaScript workflow and project-local
Node.js fallback options.

Linux-only modules are gated with `lib.mkIf pkgs.stdenv.isLinux`, so importing
this flake on macOS leaves them as no-ops without explicit skip lists.

## Bumping dependencies

Inputs are pinned in `flake.lock`. To bump them:

```bash
# Bump everything
nix --extra-experimental-features 'nix-command flakes' flake update

# Bump specific inputs (e.g. nixpkgs and home-manager)
nix --extra-experimental-features 'nix-command flakes' \
  flake update nixpkgs home-manager

# Apply the new versions
./setup.sh
```

If something breaks after a bump, roll back with `home-manager switch
--rollback`, or revert `flake.lock` (`git checkout flake.lock`) and rerun
`./setup.sh`.

## Theme sources

Catppuccin and alacritty themes come from upstream flake inputs rather than
git submodules:

- `inputs.catppuccin` — [catppuccin/nix](https://github.com/catppuccin/nix)
  metaflake; supplies waybar (and could supply more on demand)
- `inputs.catppuccin-fzf` — [catppuccin/fzf](https://github.com/catppuccin/fzf)
- `inputs.catppuccin-zellij` — [catppuccin/zellij](https://github.com/catppuccin/zellij)
- `inputs.catppuccin-yazi` — [catppuccin/yazi](https://github.com/catppuccin/yazi)
- `inputs.catppuccin-bat` — [catppuccin/bat](https://github.com/catppuccin/bat)
- `pkgs.alacritty-theme` (nixpkgs) — full alacritty-theme set, including the
  `omni` theme this repo imports

To bump theme versions:

```bash
nix --extra-experimental-features 'nix-command flakes' \
  flake update \
    catppuccin catppuccin-fzf catppuccin-zellij \
    catppuccin-yazi catppuccin-bat
./setup.sh
```

## OpenCode customization

Public config lives in `config/opencode/`. Private machine-local overrides
live in `~/.config/dotfiles/opencode/`.

| Path | Purpose |
|---|---|
| `~/.config/dotfiles/opencode/opencode.json` | main private override |
| `~/.config/dotfiles/opencode/opencode.*.json` | additional JSON fragments |
| `~/.config/dotfiles/opencode/rules/` | AGENTS/rules overlays |
| `~/.config/dotfiles/opencode/commands/` | private slash commands |
| `~/.config/dotfiles/opencode/skills/` | private skills |
| `~/.config/dotfiles/opencode/agents/` | private agents |
| `~/.config/dotfiles/opencode/plugins/` | private plugins |
| `~/.config/dotfiles/opencode/package.json` | private plugin dependency overlay |

The `home/opencode.nix` module deep-merges `opencode.json`, merges
`commands/`, `skills/`, `agents/`, and `plugins/` from public + private trees,
and links the result into `~/.config/opencode/`. Set
`programs.opencode.rulesMode` in `home/hosts/<host>.nix` to choose how
`AGENTS.md` is built (`merged`, `private_only`, or `disabled`).

After changing plugins or plugin dependencies, install dependencies with:

```bash
bun install --cwd ~/.config/opencode
```

## Adding a tool

1. Drop the public source under `config/<tool>/` (or use a Home Manager
   `programs.<tool>` module if one exists).
2. Wire it into Home Manager: a one-liner in `home/files.nix` for plain
   symlinks, or a dedicated module under `home/programs/<tool>.nix` for
   richer integrations.
3. Run `./setup.sh`.

For tools that need merging public + private content, reuse the helpers in
`home/lib/`:

- `merge-dirs.nix` — sort-merge a list of source directories, later wins
- `concat-files.nix` — concat fragments from multiple dirs, sorted together by filename
- `concat-toml-files.nix` — same but tailored to the cargo / aerospace /
  alacritty overlay-append pattern
- `deep-merge-json.nix` — recursive attrset merge for JSON-shaped configs
