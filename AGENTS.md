# Dotfiles Repo — Agent Guide

<!--toc:start-->
- [Dotfiles Repo — Agent Guide](#dotfiles-repo-agent-guide)
  - [Layout](#layout)
  - [How Setup Works](#how-setup-works)
    - [Symlink strategy](#symlink-strategy)
    - [OpenCode merges](#opencode-merges)
      - [AGENTS.md](#agentsmd)
      - [Commands, Skills, Agents, Plugins](#commands-skills-agents-plugins)
      - [opencode.json (4-tier deep merge)](#opencodejson-4-tier-deep-merge)
      - [package.json](#packagejson)
      - [Picking up private changes](#picking-up-private-changes)
    - [Overlay-append merges (Cargo, AeroSpace, Alacritty, task)](#overlay-append-merges-cargo-aerospace-alacritty-task)
  - [Private config](#private-config)
  - [OpenCode config](#opencode-config)
  - [Key invariants](#key-invariants)
<!--toc:end-->

Quick orientation for an AI agent working in this repository.

## Layout

```
dotfiles/
├── setup.sh                  # ~30-line shim that calls home-manager activation
├── flake.nix                 # Pure Home Manager flake
├── home/                     # All managed config lives here
│   ├── default.nix           # Top-level module, imports per-domain modules
│   ├── bootstrap.nix         # HM activation scripts (cleanup, task bootstrap)
│   ├── launchd-goto.nix      # Typed launchd agent for goto-api (darwin)
│   ├── files.nix             # Plain-symlink dotfiles (bat, fzf, fish, helix, kitty, ssh, …)
│   ├── lib/                  # Reusable Nix helpers (merge-dirs, concat-files, concat-toml-files, …)
│   ├── hosts/                # Per-host identity (darwin.nix, linux.nix)
│   ├── programs/             # First-class HM modules (programs.tmux, programs.git, programs.gotoLinks, …)
│   ├── desktop/              # Linux desktop (hyprland, mako, waybar, rofi)
│   ├── rust.nix              # Rust toolchain + cargo helpers
│   ├── fs.nix                # bat, eza, fd, fzf, ripgrep, yazi, zoxide, …
│   ├── shell.nix             # alacritty, kitty, fish, zellij, direnv, …
│   ├── nodejs.nix            # Bun-first JavaScript tooling
│   ├── editors.nix           # opencode, vim, vscodium, obsidian
│   ├── opencode.nix          # OpenCode merges (AGENTS.md, opencode.json, commands, …)
│   ├── helix-langs.nix       # Helix LSPs, formatters, debuggers
│   └── helix-plugins.nix     # Steel-enabled Helix with pinned plugins
├── docs/                     # Project documentation
│   └── nodejs.md             # Bun-first JavaScript setup notes
└── config/                   # Dotfile sources, grouped by tool
    ├── opencode/
    │   ├── opencode.*.json   # Per-section partials (meta, watcher, permission.{bash,fs,web}, experimental.quotaToast); deep-merged at build time
    │   ├── tui.json          # OpenCode TUI config (separate $schema; symlinked verbatim, not deep-merged)
    │   ├── package.json      # Plugin dependency manifest (deep-merged with private overlay)
    │   ├── rules/            # Public AGENTS.md fragments (sorted with private rules)
    │   ├── commands/         # OpenCode slash commands as markdown files
    │   └── skills/           # OpenCode skills, one subdirectory per skill
    ├── aerospace/            # AeroSpace base config (overlay-append into ~/.aerospace.toml)
    ├── alacritty/            # Alacritty (themes ship via pkgs.alacritty-theme)
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
    │   ├── nix-channels      # → ~/.nix-channels
    │   └── nix.conf          # → ~/.config/nix/nix.conf (flakes + parallel builds)
    ├── rofi/                 # App launcher
    ├── shell/                # bashrc, bash_profile, profile, fish_profile → $HOME
    ├── ssh/                  # ssh config (includes private overlay first)
    ├── task/                 # task base config (overlay-append) + bash completion
    ├── tmux/                 # tmux.conf + plugins/ submodules
    └── waybar/               # Status bar
```

## How Setup Works

`setup.sh` is a ~30-line shell shim that:

1. Resolves the host attribute — `thomas-darwin` on macOS, `thomas-linux` on
   Linux. `DOTFILES_HOST` overrides.
2. Runs `nix build path:.#homeConfigurations.<host>.activationPackage`.
3. Executes the resulting `activate` script.

The activation flow itself is pure HM, defined under `home/`:

1. **`home/bootstrap.nix`** runs two activation blocks:
   - `cleanupManagedDotfiles` — removes pre-existing managed symlinks
     before `checkLinkTargets` runs (idempotent; safe on a fresh machine).
   - `taskBootstrap` — runs `task bootstrap --yes` after HM linking.
2. **All other modules** under `home/` declare packages, configs, and
   symlinks. HM atomically swaps the home generation.

Identity, API URLs, and other private values are exposed by the
**private flake** at `~/.config/dotfiles/flake.nix`, which the dotfiles
flake imports as `inputs.private`. HM modules consume those values
directly: `home/programs/git.nix` reads
`inputs.private.git.{name,email,signingKey}`,
`home/programs/goto.nix` reads `inputs.private.goto.{apiUrl,bookmarksFile}`,
`home/opencode.nix` reads `inputs.private.opencode.*`, and so on. Every
field except `git.{name,email,signingKey}` is optional — HM modules use
`inputs.private.<x> or { }` defensively so a minimal private flake
(only git identity set) builds cleanly.

`setup.sh` auto-copies `private.example.nix` from the repo root into
`~/.config/dotfiles/flake.nix` on first run when the file is missing,
then exits so the user can edit the placeholders before rebuilding.

For a fully scripted first-run install, export `DOTFILES_GIT_NAME` and
`DOTFILES_GIT_EMAIL` before running `setup.sh`. `scripts/bootstrap-keys.sh`
patches both fields into the freshly-copied flake (along with `signingKey`
after generating a GPG key) and `setup.sh` skips the "edit and rerun"
exit:

```sh
DOTFILES_GIT_NAME="Your Full Name" \
DOTFILES_GIT_EMAIL="you@example.com" \
bash setup.sh
```

`scripts/bootstrap-keys.sh` also accepts `--name` and `--email` flags
when invoked directly.

When you change anything under `~/.config/dotfiles/`, just rerun `setup.sh`.
The build uses `--override-input private "path:$HOME/.config/dotfiles"`, so the
working tree is read directly with no flake.lock churn:

```sh
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

### OpenCode merges

The OpenCode merges live in `home/opencode.nix` and are built declaratively from
two reusable Nix helpers:

- `home/lib/merge-dirs.nix` — merge a list of source directories into one. Later
  sources override earlier ones on filename collision. Used for `commands`, `skills`,
  `agents`, `plugins`.
- `home/lib/concat-files.nix` — concatenate fragment files collected from a
  list of directories, sorted by filename across all sources (LC_ALL=C).
  Later directories win on filename collision. Used for `AGENTS.md`.
- `home/lib/deep-merge-json.nix` — deep-merge JSON-like attrsets. Used for
  `opencode.json` and `package.json`.

#### AGENTS.md

Public rule fragments live at `config/opencode/rules/<name>.md`. Optional private
rule fragments live at `~/.config/dotfiles/opencode/rules/<name>.md`. The HM module
collects nonempty files from both directories, sorts them together by filename in
byte order (`LC_ALL=C`), and concatenates them with `# Rules overlay: <filename>`
headers separated by blank lines. The result is written as
`~/.config/opencode/AGENTS.md`. On filename collision, the private fragment wins
(matching the convention used for commands/skills/agents/plugins).

`programs.opencode.rulesMode` (set per host in `home/hosts/<host>.nix`) controls the
behavior:

- `merged` (default): public + private fragments sorted together.
- `private_only`: only private fragments.
- `disabled`: do not manage AGENTS.md at all.

#### Commands, Skills, Agents, Plugins

Three sources contribute to each merged directory, in this order (later wins on
filename collision):

1. Public — `config/opencode/<name>/`
2. External imports — `~/.config/dotfiles/opencode-imports/<import-name>/<name>/`
   (one per entry in the imports manifest, see [External imports](#external-imports))
3. Private — `~/.config/dotfiles/opencode/<name>/`

The HM module merges all three via `mergeDirs` and exposes the result at
`~/.config/opencode/<name>/`. Private always wins; imports sit in the middle so
you can pull skills/commands/plugins from non-Nix repos without losing the
ability to override them locally.

Adding a new public command/skill/agent/plugin: drop a file (or subdirectory for
skills) into the appropriate `config/opencode/` subtree and rerun `setup.sh` so
HM picks up the change.

#### opencode.json (4-tier deep merge)

The public side is fragment-only — every section lives in its own
`opencode.<scope>.json` file (`opencode.meta.json`,
`opencode.watcher.json`, `opencode.permission.bash.json`,
`opencode.permission.fs.json`, `opencode.permission.web.json`,
`opencode.experimental.quotaToast.json`). There is intentionally no
public `opencode.json` base; the merged result is written to
`~/.config/opencode/opencode.json`.

Each tier wins over the prior one on key collision:

1. Repo fragments — `config/opencode/opencode.*.json` (sorted by filename)
2. Import fragments — `~/.config/dotfiles/opencode-imports/<name>/opencode.*.json`
   (sorted within each import; imports applied in flake-declared order)
3. Private fragments — `~/.config/dotfiles/opencode/opencode.*.json` (sorted by filename)
4. Private overlay — `~/.config/dotfiles/opencode/opencode.json`

#### package.json

Public base (`config/opencode/package.json`) is deep-merged with the optional
private overlay (`~/.config/dotfiles/opencode/package.json`). After changes, run
`bun install --cwd ~/.config/opencode` to install dependencies.

#### External imports

The imports mechanism lets you pull partial OpenCode config (skills, commands,
plugins, opencode.*.json fragments, AGENTS rules) from other repos that do not
expose Nix flakes. Declare them in `~/.config/dotfiles/flake.nix` under
`opencode.imports`. Each entry's `source` is auto-walked: every child of
`commands/`, `skills/`, `agents/`, `plugins/`, `rules/`, plus any top-level
`opencode.*.json` (excluding the bare `opencode.json`) and `package.json`, is
staged verbatim under `~/.config/dotfiles/opencode-imports/<name>/`. Drop a new
file in one of those subdirs and the next `setup.sh` picks it up — no manifest
edit required.

```nix
opencode = {
  imports = [
    # Auto-discovery only: stages every standard child of source.
    {
      name = "thomas-ai";
      source = "~/dev/repo/ai";
    }

    # Auto + tweaks. `rename` renames auto-discovered items AND imports
    # non-standard files (mcp.fragment.json doesn't match opencode.*.json
    # auto-discovery, so the rename pulls it in under the new name).
    # `exclude` skips listed source-rel paths during the auto walk.
    {
      name = "notes-vault";
      source = "~/dev/repo/notes-vault/opencode";
      rename  = { "mcp.fragment.json" = "opencode.notes.mcp.json"; };
      exclude = [ "skills/wip-skill" ];
    }

    # Cherry-pick mode: when `paths` is set, auto-discovery is OFF and
    # ONLY these mappings are imported. Mutually exclusive with
    # rename/exclude. Use this for sources where you only want a handful
    # of items, possibly under different names.
    {
      name = "philip-claude";
      source = "~/dev/repo/claude";
      paths = {
        "skills/logs"      = "skills/splunk-logs";
        "skills/gitlab-mr" = "skills/query-mr";
      };
    }
  ];
};
```

`setup.sh` reads the manifest, resolves each `source` (including `~`), and
stages the resulting files/directories under
`~/.config/dotfiles/opencode-imports/<name>/`. The staging tree mirrors the
standard opencode/ layout: subpaths starting with `commands/`, `skills/`,
`agents/`, `plugins/`, or `rules/` feed into the corresponding merge; top-level
`opencode.*.json` files feed into the JSON merge. The staging tree is gitignored
in the private repo and rewritten from scratch on every `setup.sh` run, so
removed manifest entries (and removed source files) do not linger.

#### Picking up private changes

`setup.sh` builds with `--override-input private "path:$HOME/.config/dotfiles"`,
which reads the private overlay's working tree directly (no commit required, no
flake.lock update needed). Edit anything under `~/.config/dotfiles/opencode/` or
the imports source repos, then rerun:

```sh
bash setup.sh
```

### Overlay-append merges (Cargo, AeroSpace, Alacritty, task)

These configs are built by appending overlays onto a base file:

1. **Base file** — e.g. `config/cargo/cargo-config.toml`, `config/task/config.toml`
2. **Repo overlays** — e.g. `config/cargo/cargo.darwin.toml` (platform-specific, tracked in git)
3. **Private overlays** — e.g. `~/.config/dotfiles/cargo.*.toml`, `~/.config/dotfiles/task.*.toml` (machine-local, not tracked)

Overlays are sorted by filename (byte order) within each group. Repo overlays are appended
first, then private overlays (private wins on conflict).

## Private config

Everything private lives **outside the repo** at `~/.config/dotfiles/`:

| Path | Purpose |
|---|---|
| `~/.config/dotfiles/flake.nix` | **Required.** Private flake — git identity, optional goto/opencode/homeModules wiring |
| `~/.config/dotfiles/opencode/skills/` | Private OpenCode skills (not committed) |
| `~/.config/dotfiles/opencode/commands/` | Private OpenCode commands (not committed) |
| `~/.config/dotfiles/opencode/rules/` | Private AGENTS.md rules overlays (not committed) |
| `~/.config/dotfiles/opencode/agents/` | Private OpenCode agents (not committed) |
| `~/.config/dotfiles/opencode/plugins/` | Private OpenCode plugins (not committed) |
| `~/.config/dotfiles/opencode/package.json` | Private plugin dependency overlay (not committed) |
| `~/.config/dotfiles/opencode/opencode.json` | Private OpenCode config overlay (for MCP servers and local-only overrides) |

Bootstrap `~/.config/dotfiles/flake.nix` from `private.example.nix` at the repo root
(`setup.sh` does this automatically on first run when the file is missing). Private
skills need no registration — drop a `<skill-name>/SKILL.md` directory into
`opencode/skills/` and rerun `setup.sh`.

Private commands also need no registration — drop a `<name>.md` file into
`opencode/commands/` and rerun `setup.sh`.

The OpenCode merge in `home/opencode.nix` also supports an optional
`~/.config/dotfiles/opencode/opencode.json` file. When present, it is deep-merged on top
of the public partials under `config/opencode/` (plus any `opencode.*.json` fragments
in the same private directory) to generate the merged `opencode.json` linked at
`~/.config/opencode/opencode.json`.

## OpenCode config

| File | Purpose |
|---|---|
| `config/opencode/opencode.*.json` | Per-section partials (meta, watcher, permission.{bash,fs,web}, experimental.quotaToast); deep-merged at build time |
| `config/opencode/tui.json` | OpenCode TUI config (separate `$schema`; symlinked verbatim, not deep-merged) |
| `config/opencode/rules/<name>.md` | Public AGENTS.md fragments (merged with private rules sorted by filename) |
| `config/opencode/commands/<name>.md` | Custom slash commands |
| `config/opencode/skills/<name>/SKILL.md` | Loadable skill workflows |
| `config/opencode/plugins/<name>.ts` | Global OpenCode plugins (autoloaded at startup) |
| `config/opencode/package.json` | Plugin dependency manifest |

To add a new skill: create `config/opencode/skills/<name>/SKILL.md` and register a
matching command in `config/opencode/commands/<name>.md`. Rerun `setup.sh` to add both
to the merged OpenCode config.

To add a new slash command that does not need a skill file, add it directly to the
`config/opencode/commands/` directory as a Markdown file.

## Tests

Run all tests with `nix flake check --all-systems` (or the per-arch
`nix flake check`). The flake exposes:

| Check | What it covers |
|---|---|
| `lib-runTests` | Pure unit tests via `lib.runTests`: `deep-merge-json`, `concat-files`, `list-files-in`, `home/default.nix` import resolution, `bootstrap.nix` activation-hook regression guard |
| `merge-dirs-test` | Integration test for `home/lib/merge-dirs.nix` (builds a derivation and asserts on its contents) |
| `opencode-tests` | End-to-end tests of `home/lib/opencode-merge.nix` (4-tier JSON merge, filename sort, rules modes, missing-private fallback, public-base guardrail) |
| `patch-string-field-test` | Integration test for `scripts/lib/patch-empty-string-field.sh` (empty/null/absent shapes, exit codes) |
| `configure-gpg-pinentry-test` | Integration test for `scripts/lib/configure-gpg-pinentry.sh` (idempotent rewrite of gpg-agent.conf pinentry-program lines) |

The OpenCode JSON merge and AGENTS.md composition live as pure
functions in `home/lib/opencode-merge.nix`. `home/opencode.nix`
delegates to those functions and only retains the HM-specific glue
(xdg.configFile wiring, prettyJson derivation, bun activation hook).

Tests are co-located with the code:

- `home/lib/<module>.test.nix` — pure tests next to each lib helper
- `home/lib/<module>.test/` — fixture trees for tests that need real files
- `home/opencode.test/` — end-to-end opencode merge tests + fixtures

When changing merge behaviour, update or add tests in the same
co-located directory and rerun `nix flake check`.

## Key invariants

- **Never edit** the symlinks under `~/.config/`, `~/.cargo/`, etc. directly — they
  point into `/nix/store/` and are read-only. Edit the source under `config/<tool>/`
  or the matching `home/<module>.nix`, then run `bash setup.sh`.
- Setup must stay idempotent and work with a minimal private flake (only the
  required `git.{name,email,signingKey}` fields set; everything else null/omitted).
- New tools must not be introduced unless already present in the Nix flake or the project.
