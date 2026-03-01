# Dotfiles workflow

This dotfiles repo now includes a cross-machine OpenCode + worktree setup.

## Install

```bash
./setup.sh
```

That script links your dotfiles, installs the Nix flake toolchain from your local dotfiles path (`path:<dotfiles>/home/flakes#toolchain`), creates `~/dev/repos` and `~/dev/wt`, and runs `task bootstrap`.

## Daily flow

```bash
task start git@github.com:org/repo.git feat/my-branch
task done
task clean github.com/org/repo feat/my-branch
```

- Bare repos: `~/dev/repos/<repo>.git`
- Worktrees: `~/dev/wt/<repo>/<branch>`

## What is `task`?

`task` is your local workflow helper script, linked to `~/.local/bin/task` from `home/bin/task`.

It automates your day-to-day repo flow:

- bare repo clone storage in `~/dev/repos`
- per-branch git worktree creation in `~/dev/wt`
- opening VSCodium and attaching/switching tmux sessions
- auto-running `asdf install` when `.tool-versions` exists
- running Rust + JS check pipelines with `task done`

## Cheatsheet

```bash
# setup / health
./setup.sh
task bootstrap
task doctor

# repo bootstrap (one-time per repo)
task clone git@github.com:org/repo.git

# start work on a branch (creates worktree if missing)
task start github.com/org/repo feat/my-ticket

# short repo names work when unique locally
task start goto feat/my-ticket

# same as above, directly from URL
task start git@github.com:org/repo.git feat/my-ticket

# reopen existing worktree/session
task open github.com/org/repo feat/my-ticket

# park current task (run from inside the task worktree)
task park

# print expected worktree path
task path github.com/org/repo feat/my-ticket

# list tasks with status (open or parked)
task list
task list github.com/org/repo

# raw git worktree output
task worktrees
task worktrees github.com/org/repo

# run project checks from a worktree
task done

# remove a clean worktree
task clean github.com/org/repo feat/my-ticket

# force-remove dirty worktree
task clean github.com/org/repo feat/my-ticket --force

# prune stale worktree metadata
task prune github.com/org/repo

# alias
wt <same-subcommands-as-task>

# model switch wrappers
oc-codex
oc-claude
```

Tab completion for `task`/`wt` is configured for Fish (`config/fish/completions/task.fish`) and Bash (`home/task.bash-completion`).

When multiple local repos match a short name, `task` asks you to choose (via `fzf` when interactive).

`task park` takes no arguments and detects the current task from your working directory.

## AI model switching

- `oc-codex` -> OpenAI Codex model
- `oc-claude` -> Anthropic Claude model

OpenCode config is at `config/opencode/opencode.json`.

### Private OpenCode overrides (MCP, local-only)

Use `~/.config/dotfiles/private-opencode.json` for private OpenCode settings you do not want in git.
`setup.sh` deep-merges it over `config/opencode/opencode.json` and generates
`~/.local/share/dotfiles/opencode/opencode.json`, then links that to `~/.config/opencode/opencode.json`.

Example GitLab MCP config:

```json
{
  "mcp": {
    "GitLab": {
      "type": "remote",
      "url": "https://gitlab.example.com/api/v4/mcp",
      "enabled": true
    }
  }
}
```

After updating your private file:

```bash
./setup.sh
opencode mcp auth GitLab
opencode mcp list
```

## Notifications (Hyprland)

- Notification daemon: `mako` (Wayland-native)
- Config path: `config/mako/config`
- Hyprland autostart: `exec-once = mako &` in `config/hypr/hyprland.conf`
- Position: top-right

## Node.js policy

Node.js is managed by `asdf`.

- Global default: `home/tool-versions` (currently `nodejs 25.6.1`)
- Project overrides: commit `.tool-versions` per repo
- Package manager: `pnpm` via Corepack
