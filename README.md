# Dotfiles

Shell, editor, terminal, window manager, SSH, task, and OpenCode config managed
from one place via [Home Manager](https://nix-community.github.io/home-manager/).

## Quick start

Prerequisite: install [Nix](https://nixos.org).

```bash
./setup.sh
$EDITOR ~/.config/dotfiles/flake.nix
./setup.sh
```

The first run copies `private.example.nix` to
`~/.config/dotfiles/flake.nix` and exits. Fill in
`git.{name,email,signingKey}`, then run setup again to build and activate the
Home Manager generation.

After setup:

- restart your shell
- run `task doctor`
- if you use OpenCode, run it once and connect any MCP servers you have
  configured

## What to edit where

- shared config: edit files under `config/<tool>/` or `home/<module>.nix`
- per-host wiring: edit `home/hosts/<host>.nix` (rules mode, identity
  overrides, etc.)
- private machine-specific config: put it under `~/.config/dotfiles/`

After changing anything, rerun `./setup.sh`. It auto-detects the host; set
`DOTFILES_HOST` only when you need to override that.

Common private overlays:

- `~/.config/dotfiles/flake.nix`: the only required file. Sets git identity
  and wires in optional overlays. Bootstrap from `private.example.nix`.
- `~/.config/dotfiles/extra.gitconfig`: extra gitconfig included from
  `~/.config/git/config` when `git.extraConfigInclude` points at it
- `~/.config/dotfiles/ssh/config`: private SSH hosts and `IdentityFile` paths
- `~/.config/dotfiles/goto/database.yml`: private goto bookmarks
- `~/.config/dotfiles/opencode/`: private OpenCode overlays
- `~/.config/dotfiles/task.<name>.toml`: private task overlays
- `~/.config/dotfiles/cargo.<name>.toml`: private cargo overlays
- `~/.config/dotfiles/aerospace.<name>.toml`: private AeroSpace rules
- `~/.config/dotfiles/opencode/{opencode*.json,rules,commands,skills,agents,plugins,package.json}`:
  private OpenCode config

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
this flake on macOS leaves them as no-ops automatically.

## Bumping dependencies

Most dependencies are Nix flake inputs pinned in `flake.lock`. If your Nix
install already enables flakes, omit the `--extra-experimental-features` prefix.

To bump all inputs and apply the new generation:

```bash
nix --extra-experimental-features 'nix-command flakes' flake update
./setup.sh
```

To bump specific inputs only, name them explicitly:

```bash
nix --extra-experimental-features 'nix-command flakes' \
  flake update nixpkgs home-manager
```

`nixgl-nixpkgs` is intentionally pinned alongside a known-good nixGL commit;
avoid changing that input unless you are explicitly testing Linux OpenGL.

OpenCode plugin dependencies are declared in `config/opencode/package.json` and
the optional private package overlay. After changing those package versions,
run `./setup.sh`; activation automatically runs `bun install` for
`~/.config/opencode` when the merged package file changes.

If something breaks after a bump, roll back with `home-manager switch
--rollback`, or revert `flake.lock` (`git checkout flake.lock`) and rerun
`./setup.sh`.

Set `programs.opencode.rulesMode` in `home/hosts/<host>.nix` to choose how
OpenCode `AGENTS.md` is built: `merged`, `private_only`, or `disabled`.
