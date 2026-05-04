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
│   ├── merge.rs              # Cargo, AeroSpace, Alacritty overlay-append merges
│   └── external.rs           # Home Manager activation, task bootstrap
├── dotfiles.example.toml     # Template; real file lives at ~/.config/dotfiles/config.toml
├── home/                     # Home Manager flake — owns all package installs
│   ├── default.nix           # Top-level module, imports per-domain modules
│   ├── lib/                  # Reusable Nix helpers (merge-dirs, concat-files, …)
│   ├── hosts/                # Per-host identity (darwin.nix, linux.nix)
│   ├── programs/             # First-class HM modules (programs.tmux, programs.git)
│   ├── desktop/              # Linux desktop (hyprland, mako, waybar, rofi)
│   ├── rust.nix              # Rust toolchain + cargo helpers
│   ├── fs.nix                # bat, eza, fd, fzf, ripgrep, yazi, zoxide, …
│   ├── shell.nix             # alacritty, kitty, fish, zellij, direnv, …
│   ├── editors.nix           # opencode, vim, vscodium, obsidian
│   ├── opencode.nix          # OpenCode merges (AGENTS.md, opencode.json, commands, …)
│   ├── helix-langs.nix       # Helix LSPs, formatters, debuggers
│   └── helix-plugins.nix     # Steel-enabled Helix with pinned plugins
└── config/                   # Dotfile sources, grouped by tool
    ├── opencode/
    │   ├── opencode.json     # OpenCode config (model, permissions, MCP)
    │   ├── AGENTS.md         # OpenCode system prompt (loaded in every session)
    │   ├── commands/         # OpenCode slash commands as markdown files
    │   └── skills/           # OpenCode skills, one subdirectory per skill
    ├── aerospace/            # AeroSpace base config (overlay-append into ~/.aerospace.toml)
    ├── alacritty/            # Alacritty + themes submodule
    ├── asdf/                 # tool-versions → ~/.tool-versions
    ├── cargo/                # cargo-config.toml + platform overlays → ~/.cargo/config.toml
    ├── espflash/             # ESP flashing tool
    ├── fish/                 # Fish shell XDG config (full-dir symlink to ~/.config/fish/)
    ├── git/                  # gitconfig template → ~/.gitconfig
    ├── goto/                 # goto config template (private values injected by setup)
    ├── helix/                # Helix editor
    ├── hypr/                 # Hyprland WM
    ├── kitty/                # Terminal emulator
    ├── mako/                 # Notification daemon
    ├── nix/
    │   └── nix-channels      # → ~/.nix-channels
    ├── rofi/                 # App launcher
    ├── shell/                # bashrc, bash_profile, profile, fish_profile → $HOME
    ├── ssh/                  # ssh config (includes private overlay first)
    ├── task/                 # task base config (overlay-append) + bash completion
    ├── tmux/                 # tmux.conf + plugins/ submodules
    └── waybar/               # Status bar
```

## How setup works

`setup.sh` is a thin shell shim that builds and runs the Rust setup tool
(`setup/`). It tries `cargo run` first, falls back to `nix run path:./setup`.

The setup tool is idempotent — run it any time to re-apply. Use `--check` to
verify that generated files match the current output without changing anything.

1. **Records** the dotfiles path to `~/.config/dotfiles/path`.
2. **Links** files from `config/` into the appropriate `$HOME` and `$HOME/.config/` paths.
3. **Builds merged OpenCode AGENTS, commands, and skills** — see below.
4. **Activates the Home Manager generation** defined in `home/` for the current host
   (`thomas-darwin` on macOS, `thomas-linux` on Linux). HM owns the package set:
   Rust, Git, filesystem, shell, editor, desktop, Helix language, and Helix plugin tooling.
   `DOTFILES_HOST` overrides host detection.
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

### OpenCode merges (HM-owned, since Phase 3)

The OpenCode merges live in `home/opencode.nix` and are built declaratively from
two reusable Nix helpers:

- `home/lib/merge-dirs.nix` — merge a list of source directories into one. Later
  sources override earlier ones on filename collision. Used for `commands`, `skills`,
  `agents`, `plugins`.
- `home/lib/concat-files.nix` — concatenate an optional base file plus overlay
  fragments from a list of directories. Used for `AGENTS.md`. Substitutes
  `__DOTFILES_PATH__` to the live repo path.
- `home/lib/deep-merge-json.nix` — deep-merge JSON-like attrsets. Used for
  `opencode.json` and `package.json`.

#### AGENTS.md

Public AGENTS lives at `config/opencode/AGENTS.md`. Optional private rules overlays
live at `~/.config/dotfiles/opencode/rules/<name>.md`. The HM module concatenates
the public base (when `programs.opencode.rulesMode = "merged"`) plus each non-empty
overlay file from that directory, sorted by filename in byte order (`LC_ALL=C`),
each preceded by `# Rules overlay: <filename>`. The result is written as
`~/.config/opencode/AGENTS.md`.

`programs.opencode.rulesMode` (set per host in `home/hosts/<host>.nix`) controls the
behavior:

- `merged` (default): public base + private overlays.
- `private_only`: only private overlays.
- `disabled`: do not manage AGENTS.md at all.

#### Commands, skills, agents, plugins

Public sources live at `config/opencode/<name>/`. Private sources live at
`~/.config/dotfiles/opencode/<name>/`. The HM module merges them via
`mergeDirs` and exposes the result at `~/.config/opencode/<name>/`. On filename
collision, the private entry wins.

Adding a new public command/skill/agent/plugin: drop a file (or subdirectory for
skills) into the appropriate `config/opencode/` subtree and re-run `setup.sh` so
HM picks up the change.

#### opencode.json (4-tier deep merge)

Each tier wins over the previous on key collision:

1. Public base — `config/opencode/opencode.json`
2. Repo fragments — `config/opencode/opencode.*.json` (sorted by filename)
3. Private fragments — `~/.config/dotfiles/opencode/opencode.*.json` (sorted by filename)
4. Private overlay — `~/.config/dotfiles/opencode/opencode.json`

#### package.json

Public base (`config/opencode/package.json`) is deep-merged with the optional
private overlay (`~/.config/dotfiles/opencode/package.json`). After changes, run
`bun install --cwd ~/.config/opencode` to install dependencies.

#### Picking up private changes

The private overlay is consumed as a flake input pinned by `flake.lock`. When you
add or modify files under `~/.config/dotfiles/opencode/`, refresh the lock so HM
picks up the change:

```sh
nix --extra-experimental-features 'nix-command flakes' flake update private --flake .
bash setup.sh
```

### Overlay-append merges (Cargo, AeroSpace, Alacritty, task)

These configs are built by appending overlays onto a base file:

1. **Base file** — e.g. `config/cargo/cargo-config.toml`, `config/task/config.toml`
2. **Repo overlays** — e.g. `config/cargo/cargo.darwin.toml` (platform-specific, tracked in git)
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
  platform-specific overlays (e.g. skip `config/cargo/cargo.darwin.toml` on Linux).

Source filtering happens before merge; destination filtering happens at link time.

> `skip_links` is a deprecated alias for `skip_destinations`.

## Private config

Everything private lives **outside the repo** at `~/.config/dotfiles/`:

| Path | Purpose |
|---|---|
| `~/.config/dotfiles/config.toml` | Git identity, API URLs, trusted roots |
| `~/.config/dotfiles/opencode/skills/` | Private OpenCode skills (not committed) |
| `~/.config/dotfiles/opencode/commands/` | Private OpenCode commands (not committed) |
| `~/.config/dotfiles/opencode/rules/` | Private AGENTS.md rules overlays (not committed) |
| `~/.config/dotfiles/opencode/agents/` | Private OpenCode agents (not committed) |
| `~/.config/dotfiles/opencode/plugins/` | Private OpenCode plugins (not committed) |
| `~/.config/dotfiles/opencode/package.json` | Private plugin dependency overlay (not committed) |
| `~/.config/dotfiles/opencode/opencode.json` | Private OpenCode config overlay (for MCP servers and local-only overrides) |

Copy `dotfiles.example.toml` to get started. Private skills need no registration — drop a
`<skill-name>/SKILL.md` directory into `opencode/skills/` and re-run `setup.sh`.

Private commands also need no registration — drop a `<name>.md` file into
`opencode/commands/` and re-run `setup.sh`.

The setup tool also supports an optional `~/.config/dotfiles/opencode/opencode.json` file.
When present, it is deep-merged over `config/opencode/opencode.json` to generate
`~/.local/share/dotfiles/opencode/opencode.json`, and `~/.config/opencode/opencode.json`
points to that generated merged file.

## OpenCode config

| File | Purpose |
|---|---|
| `config/opencode/opencode.json` | Model selection, bash permissions, MCP config |
| `config/opencode/AGENTS.md` | System prompt injected into every OpenCode session |
| `config/opencode/commands/<name>.md` | Custom slash commands |
| `config/opencode/skills/<name>/SKILL.md` | Loadable skill workflows |
| `config/opencode/plugins/<name>.ts` | Global OpenCode plugins (auto-loaded at startup) |
| `config/opencode/package.json` | Plugin dependency manifest |

To add a new skill: create `config/opencode/skills/<name>/SKILL.md` and register a
matching command in `config/opencode/commands/<name>.md`. Re-run `setup.sh` to add both
to the merged OpenCode config.

To add a new slash command that does not need a skill file, add it directly to the
`config/opencode/commands/` directory as a markdown file.

## Key invariants

- **Never edit** files under `~/.local/share/dotfiles/` directly — they are generated.
- **Never edit** `~/.gitconfig`, `~/.config/goto/config.yml`, or `~/.config/task/config.toml`
  directly — edit the templates in `dotfiles/` instead.
- Setup must stay idempotent and work without `config.toml` present.
- New tools must not be introduced unless already present in the Nix flake or the project.
