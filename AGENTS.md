# Dotfiles Repo — Agent Guide

Quick orientation for an AI agent working in this repository.

## Layout

```
dotfiles/
├── setup.sh                  # Thin shim — runs the Rust setup tool via nix or cargo
├── Cargo.toml                # Rust setup tool (dotfiles-setup)
├── flake.nix                 # nix run entry point
├── src/
│   ├── main.rs               # CLI (--check flag), orchestration
│   ├── config.rs             # Private TOML config parsing, path resolution
│   ├── link.rs               # Symlink operations (managed_link, skip-links, cleanup)
│   ├── merge.rs              # AGENTS.md, opencode.json, skills, overlay-append merges
│   ├── generate.rs           # Template substitution (gitconfig, goto, task)
│   └── external.rs           # Nix toolchain install, task bootstrap
├── config.toml.example        # Template; real file lives at ~/.config/dotfiles/config.toml
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
│   ├── goto/                 # goto config template (private values injected by setup)
│   └── task/                 # task base config (overlay-append pattern, see below)
└── home/                     # Files symlinked directly into $HOME
    ├── gitconfig             # Git config template (private values injected by setup)
    ├── flakes/               # Nix flakes directory
    │   └── toolchain/        # Toolchain flake — defines the dev profile
    ├── tmux/                 # tmux plugins
    ├── tmux.conf
    ├── profile / bashrc / bash_profile / fish_profile
    ├── nix-channels
    ├── tool-versions         # asdf global tool versions
    └── task.bash-completion
```

## How setup works

`setup.sh` is a thin shell shim that builds and runs the Rust setup tool
(`setup/`). It tries `cargo run` first, falls back to `nix run path:./setup`.

The setup tool is idempotent — run it any time to re-apply. Use `--check` to
verify that generated files match the current output without changing anything.

1. **Records** the dotfiles path to `~/.config/dotfiles/path`.
2. **Links** files from `home/` and `config/` into `$HOME` using symlinks.
3. **Builds merged OpenCode AGENTS and skills** — see below.
4. **Installs the Nix toolchain** from `home/flakes/toolchain#toolchain` via `nix profile`.
5. **Reads** `~/.config/dotfiles/config.toml` (if present) to inject private values
   (git identity, API URLs) into generated files under `~/.local/share/dotfiles/`,
   then symlinks those into `~/.config/`.
6. Runs `task bootstrap`.

### Symlink strategy

Most config is a direct symlink: `~/.config/fish -> dotfiles/config/fish`.
Edit the source in `dotfiles/`; the symlink makes it live immediately.

**Exception — generated files:** `~/.gitconfig` and `~/.config/goto/config.yml` are
*generated* from templates + private values. Never edit them directly; edit the
template in `dotfiles/` and re-run `setup.sh`.

### AGENTS merge

Public AGENTS lives at `config/opencode/AGENTS.md`. Optional private rules overlays live at
`~/.config/dotfiles/opencode/rules/`.

The setup tool builds a merged file at `~/.local/share/dotfiles/opencode/AGENTS.md` by
copying the public AGENTS and appending each non-empty readable file from that directory,
sorted by filename (byte order, equivalent to `LC_ALL=C`).
`~/.config/opencode/AGENTS.md` then points at this generated file.

### Skills merge

Public skills (`config/opencode/skills/<name>/`) and private skills
(`~/.config/dotfiles/opencode/skills/<name>/`) are merged into a real
directory at `~/.local/share/dotfiles/opencode/skills/`, with each skill as a symlink
inside it. `~/.config/opencode/skills` then points at this merge directory.

This means adding a new public skill only requires creating the subdirectory here and
re-running `setup.sh` (or manually adding a symlink to the merge dir).

### Agents merge

Public agents (`config/opencode/agents/<name>.md`) and private agents
(`~/.config/dotfiles/opencode/agents/<name>.md`) are merged into a real directory at
`~/.local/share/dotfiles/opencode/agents/`, with each agent as a symlink inside it.
`~/.config/opencode/agents` then points at this merge directory.

Private agents overwrite public ones on filename collision. Adding a new public agent only
requires placing a `.md` file in `config/opencode/agents/` and re-running `setup.sh`.

### Plugins merge

Public plugins (`config/opencode/plugins/<name>.ts`) and private plugins
(`~/.config/dotfiles/opencode/plugins/<name>.ts`) are merged into a real directory at
`~/.local/share/dotfiles/opencode/plugins/`, with each plugin as a symlink inside it.
`~/.config/opencode/plugins` then points at this merge directory.

Private plugins overwrite public ones on filename collision. After changing plugins,
run `bun install --cwd ~/.config/opencode` to install any new dependencies.

### package.json merge

Public base (`config/opencode/package.json`) and optional private overlay
(`~/.config/dotfiles/opencode/package.json`) are deep-merged into
`~/.local/share/dotfiles/opencode/package.json`. `~/.config/opencode/package.json`
then points at this generated file.

If neither source exists, no output is produced. After `setup.sh`, run
`bun install --cwd ~/.config/opencode` to install plugin dependencies.

### Overlay-append merges (Cargo, AeroSpace, Alacritty, task)

These configs are built by appending overlays onto a base file:

1. **Base file** — e.g. `home/cargo-config.toml`, `config/task/config.toml`
2. **Repo overlays** — e.g. `home/cargo.darwin.toml` (platform-specific, tracked in git)
3. **Private overlays** — e.g. `~/.config/dotfiles/cargo.*.toml`, `~/.config/dotfiles/task.*.toml` (machine-local, not tracked)

Overlays are sorted by filename (byte order) within each group. Repo overlays are appended
first, then private overlays (private wins on conflict).

### Skip lists

Two skip lists in `config.toml` control what gets linked/merged:

- **`skip_destinations`** — suffix-matched against the destination path relative to `$HOME`.
  Prevents a managed symlink or merge output from being created. Use this to omit
  platform-specific outputs (e.g. skip `.config/hypr` on macOS).
- **`skip_sources`** — suffix-matched against source paths relative to the dotfiles repo root.
  Prevents a source file from being linked or included in a merge. Use this to exclude
  platform-specific overlays (e.g. skip `home/cargo.darwin.toml` on Linux).

Source filtering happens before merge; destination filtering happens at link time.

> `skip_links` is a deprecated alias for `skip_destinations`.

## Private config

Everything private lives **outside the repo** at `~/.config/dotfiles/`:

| Path | Purpose |
|---|---|
| `~/.config/dotfiles/config.toml` | Git identity, API URLs, trusted roots |
| `~/.config/dotfiles/opencode/skills/` | Private OpenCode skills (not committed) |
| `~/.config/dotfiles/opencode/rules/` | Private AGENTS.md rules overlays (not committed) |
| `~/.config/dotfiles/opencode/agents/` | Private OpenCode agents (not committed) |
| `~/.config/dotfiles/opencode/plugins/` | Private OpenCode plugins (not committed) |
| `~/.config/dotfiles/opencode/package.json` | Private plugin dependency overlay (not committed) |
| `~/.config/dotfiles/opencode/opencode.json` | Private OpenCode config overlay (for MCP servers and local-only overrides) |

Copy `config.toml.example` to get started. Private skills need no registration — drop a
`<skill-name>/SKILL.md` directory into `opencode/skills/` and re-run `setup.sh`.

The setup tool also supports an optional `~/.config/dotfiles/opencode/opencode.json` file.
When present, it is deep-merged over `config/opencode/opencode.json` to generate
`~/.local/share/dotfiles/opencode/opencode.json`, and `~/.config/opencode/opencode.json`
points to that generated merged file.

## OpenCode config

| File | Purpose |
|---|---|
| `config/opencode/opencode.json` | Model selection, slash commands, bash permissions |
| `config/opencode/AGENTS.md` | System prompt injected into every OpenCode session |
| `config/opencode/skills/<name>/SKILL.md` | Loadable skill workflows |
| `config/opencode/plugins/<name>.ts` | Global OpenCode plugins (auto-loaded at startup) |
| `config/opencode/package.json` | Plugin dependency manifest |

To add a new skill: create `config/opencode/skills/<name>/SKILL.md` and register a
matching command in `opencode.json` (see existing commands for the pattern). Re-run
`setup.sh` to add it to the merge dir.

To add a new slash command that does not need a skill file, add it directly to the
`command` block in `opencode.json`.

## Key invariants

- **Never edit** files under `~/.local/share/dotfiles/` directly — they are generated.
- **Never edit** `~/.gitconfig`, `~/.config/goto/config.yml`, or `~/.config/task/config.toml`
  directly — edit the templates in `dotfiles/` instead.
- Setup must stay idempotent and work without `config.toml` present.
- New tools must not be introduced unless already present in the Nix flake or the project.
