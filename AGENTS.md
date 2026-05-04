# Dotfiles Repo — Agent Guide

Quick orientation for an AI agent working in this repository.

## Layout

```
dotfiles/
├── setup.sh                  # ~30-line shim that calls home-manager activation
├── flake.nix                 # Pure Home Manager flake
├── home/                     # All managed config lives here
│   ├── default.nix           # Top-level module, imports per-domain modules
│   ├── bootstrap.nix         # HM activation scripts (cleanup, path record, task bootstrap)
│   ├── launchd.nix           # macOS LaunchAgents (Library/LaunchAgents/*.plist)
│   ├── files.nix             # Plain-symlink dotfiles (bat, fzf, fish, helix, kitty, ssh, …)
│   ├── lib/                  # Reusable Nix helpers (merge-dirs, concat-files, concat-toml-files, …)
│   ├── hosts/                # Per-host identity (darwin.nix, linux.nix)
│   ├── programs/             # First-class HM modules (programs.tmux, programs.git, programs.gotoLinks, …)
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

`setup.sh` is a ~30-line shell shim that:

1. Resolves the host attribute — `thomas-darwin` on macOS, `thomas-linux` on
   Linux. `DOTFILES_HOST` overrides.
2. Runs `nix build path:.#homeConfigurations.<host>.activationPackage`.
3. Executes the resulting `activate` script.

The activation flow itself is pure HM, defined under `home/`:

1. **`home/bootstrap.nix`** runs three activation blocks:
   - `cleanupLegacyDotfiles` — removes Rust-managed symlinks from earlier
     phases (idempotent; safe on a fresh machine).
   - `recordDotfilesPath` — writes the live repo path to
     `~/.config/dotfiles/path` so private flake imports can resolve it.
   - `taskBootstrap` — runs `task bootstrap --yes` after HM linking.
2. **All other modules** under `home/` declare packages, configs, and
   symlinks. HM atomically swaps the home generation.

Identity, API URLs, and other private values are read from
`~/.config/dotfiles/config.toml` by the **private flake** at
`~/.config/dotfiles/flake.nix`, which the dotfiles flake imports as
`inputs.private`. The HM module `home/programs/git.nix` (and others)
consume those values via `inputs.private.git.{name,email,signingKey}` etc.

When you change anything under `~/.config/dotfiles/`, refresh the flake input:

```sh
nix --extra-experimental-features 'nix-command flakes' flake update private --flake .
bash setup.sh
```

### Symlink strategy

Most config is a symlink to a /nix/store path managed by Home Manager.
Source content lives in `config/<tool>/...` and is wired in by the
matching `home/files.nix` or `home/programs/<tool>.nix` module.

The HM symlinks are read-only (they target /nix/store). To change a
config, edit the source under `config/`, then run `bash setup.sh` so
HM rebuilds the generation and updates the symlink.

**Generated files** (built by HM rather than symlinked verbatim):

- `~/.config/git/config` — built from typed options + identity from the private flake
- `~/.config/goto/config.yml` — built from `programs.gotoLinks` options
- `~/.config/task/config.toml` — built from `programs.task` options + private overlays
- `~/.config/opencode/{AGENTS.md, opencode.json, package.json, commands, skills, agents, plugins}` — built from public + private overlays
- `~/.cargo/config.toml`, `~/.aerospace.toml`, `~/.config/alacritty/alacritty.toml` — base + platform + private overlays concatenated

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

Source filtering happens before merge; destination filtering happens at link time.

> `skip_links` is a deprecated alias for `skip_destinations`.

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
the merged `opencode.json` linked at `~/.config/opencode/opencode.json`.

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

- **Never edit** the symlinks under `~/.config/`, `~/.cargo/`, etc. directly — they
  point into `/nix/store/` and are read-only. Edit the source under `config/<tool>/`
  or the matching `home/<module>.nix`, then run `bash setup.sh`.
- Setup must stay idempotent and work without `config.toml` present.
- New tools must not be introduced unless already present in the Nix flake or the project.
