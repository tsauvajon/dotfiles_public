# Dotfiles Repo — Agent Guide

Quick orientation for an AI agent working in this repository.

## Layout

```
dotfiles/
├── setup.sh                  # Single entry point — run to apply everything
├── private.toml.example      # Template; real file lives at ~/.config/dotfiles/private.toml
├── config/                   # XDG config files, symlinked into ~/.config/
│   ├── opencode/
│   │   ├── opencode.json     # OpenCode config (model, commands, permissions)
│   │   ├── AGENTS.md         # OpenCode system prompt (loaded in every session)
│   │   └── skills/           # OpenCode skills, one subdirectory per skill
│   ├── fish/                 # Fish shell config
│   ├── hypr/                 # Hyprland WM
│   ├── kitty/                # Terminal emulator
│   ├── waybar/               # Status bar
│   ├── mako/                 # Notification daemon
│   ├── rofi/                 # App launcher
│   ├── espflash/             # ESP flashing tool
│   ├── goto/                 # goto config template (private values injected by setup.sh)
│   └── task/                 # task config template (private values injected by setup.sh)
└── home/                     # Files symlinked directly into $HOME
    ├── gitconfig             # Git config template (private values injected by setup.sh)
    ├── flakes/               # Nix flakes directory
    │   └── toolchain/        # Toolchain flake — defines the dev profile
    ├── tmux/                 # tmux plugins
    ├── tmux.conf
    ├── profile / bashrc / bash_profile / fish_profile
    ├── nix-channels
    ├── tool-versions         # asdf global tool versions
    └── task.bash-completion
```

## How setup.sh works

`setup.sh` is idempotent — run it any time to re-apply.

1. **Records** the dotfiles path to `~/.config/dotfiles/path`.
2. **Links** files from `home/` and `config/` into `$HOME` using `ln -snf`.
3. **Builds merged OpenCode AGENTS and skills** — see below.
4. **Installs the Nix toolchain** from `home/flakes/toolchain#toolchain` via `nix profile`.
5. **Reads** `~/.config/dotfiles/private.toml` (if present) to inject private values
   (git identity, API URLs, trusted workspace roots) into generated files under
   `~/.local/share/dotfiles/`, then symlinks those into `~/.config/`.
6. Runs `task bootstrap`.

### Symlink strategy

Most config is a direct symlink: `~/.config/fish → dotfiles/config/fish`.  
Edit the source in `dotfiles/`; the symlink makes it live immediately.

**Exception — generated files:** `~/.gitconfig`, `~/.config/goto/config.yml`, and
`~/.config/task/config.toml` are *generated* by `setup.sh` from templates + private values.
Never edit them directly; edit the template in `dotfiles/` and re-run `setup.sh`.

### AGENTS merge

Public AGENTS lives at `config/opencode/AGENTS.md`. Optional private AGENTS overlays live at
`~/.config/dotfiles/private-AGENTS/`.

`setup.sh` builds a merged file at `~/.local/share/dotfiles/opencode/AGENTS.md` by
copying the public AGENTS and appending each non-empty readable file from that directory,
sorted by filename (`LC_ALL=C`).
`~/.config/opencode/AGENTS.md` then points at this generated file.

### Skills merge

Public skills (`config/opencode/skills/<name>/`) and private skills
(`~/.config/dotfiles/private-skills/<name>/`) are merged by `setup.sh` into a real
directory at `~/.local/share/dotfiles/opencode/skills/`, with each skill as a symlink
inside it. `~/.config/opencode/skills` then points at this merge directory.

This means adding a new public skill only requires creating the subdirectory here and
re-running `setup.sh` (or manually adding a symlink to the merge dir).

## Private config

Everything private lives **outside the repo** at `~/.config/dotfiles/`:

| Path | Purpose |
|---|---|
| `~/.config/dotfiles/private.toml` | Git identity, API URLs, trusted roots |
| `~/.config/dotfiles/private-skills/` | Private OpenCode skills (not committed) |
| `~/.config/dotfiles/private-AGENTS/` | Private OpenCode prompt overlays (not committed) |
| `~/.config/dotfiles/private-opencode.json` | Private OpenCode config overlay (for MCP servers and local-only overrides) |

Copy `private.toml.example` to get started. Private skills need no registration — drop a
`<skill-name>/SKILL.md` directory into `private-skills/` and re-run `setup.sh`.

`setup.sh` also supports an optional `~/.config/dotfiles/private-opencode.json` file. When
present, it is deep-merged over `config/opencode/opencode.json` to generate
`~/.local/share/dotfiles/opencode/opencode.json`, and `~/.config/opencode/opencode.json`
points to that generated merged file.

## OpenCode config

| File | Purpose |
|---|---|
| `config/opencode/opencode.json` | Model selection, slash commands, bash permissions |
| `config/opencode/AGENTS.md` | System prompt injected into every OpenCode session |
| `config/opencode/skills/<name>/SKILL.md` | Loadable skill workflows |

To add a new skill: create `config/opencode/skills/<name>/SKILL.md` and register a
matching command in `opencode.json` (see existing commands for the pattern). Re-run
`setup.sh` to add it to the merge dir.

To add a new slash command that does not need a skill file, add it directly to the
`command` block in `opencode.json`.

## Key invariants

- **Never edit** files under `~/.local/share/dotfiles/` directly — they are generated.
- **Never edit** `~/.gitconfig`, `~/.config/goto/config.yml`, or `~/.config/task/config.toml`
  directly — edit the templates in `dotfiles/` instead.
- `setup.sh` must stay idempotent and work without `private.toml` present.
- New tools must not be introduced unless already present in the Nix flake or the project.
