---
name: task
description: Use `task` for repo/worktree/detach workflows — creating feature tasks, exploring a repo's main branch via detached worktrees, and installing project binaries from detach configs.
compatibility: opencode
---

# task workflow

`task` is a Rust workflow helper (`github.com/tsauvajon/task`) that manages three things:

1. **Bare clones** of repos, stored under `~/dev/repos/`.
2. **Detached worktrees** pinned to each repo's default branch, stored under `~/dev/detached/`. Used for reading `main`/`master` and as the source for `cargo install`.
3. **Task worktrees** (one per feature branch) stored under `~/dev/wt/`. Each task gets its own directory and tmux session.

Run `task --help` for the full command list; this skill focuses on the flows you actually use day-to-day.

## Directory layout

All paths use `~` (your `$HOME`).

| Path | Purpose |
|---|---|
| `~/dev/repos/<host>/<path>.git` | Bare clone — source of truth for a repo |
| `~/dev/detached/<host>/<path>/` | Worktree pinned to the default branch (read-only main) |
| `~/dev/wt/<host>/<path>/<branch>/` | Feature-branch worktree. Slashes in the branch name become nested directories (e.g. `feat/T-123/desc` → three levels) |

Config lives in two files:

- `~/.config/task/config.toml` — base config (committed in dotfiles as `config/task/config.toml`).
- `~/.config/dotfiles/task.*.toml` — private overlays (machine-local, not tracked). Appended onto the base by `setup.sh`.

The base config defines `repos_dir`, `wt_dir`, `detached_dir`, and a list of installable binaries.

## Task worktrees (feature work)

### Create / open a task

```bash
task start <host>/<group>/<repo> <branch> [base_ref]
```

- Clones the repo into `~/dev/repos/` if needed.
- Creates a new worktree under `~/dev/wt/<host>/<group>/<repo>/<branch>/`.
- Opens tmux, opencode, and vscodium in the new worktree.
- Add `--no-open` to skip opening tools.

Example (generic):

```bash
task start <host>/<group>/<repo> feat/<ticket>/<short-desc>
```

### Park, re-open, finish

```bash
task park                            # stop the current task's tmux session (worktree stays)
task open [repo] [branch]            # re-attach to a parked task
task finish [repo] [branch] [--force]  # remove the worktree when done
```

With no arguments, `task open` / `task finish` / `task park` act on the current task (inferred from the cwd).

### Inspect state

```bash
task list        # table of open vs parked tasks
task ui          # interactive TUI
task path [repo] [branch]   # print worktree path (useful in scripts: cd "$(task path)")
task worktrees   # raw `git worktree list` output
```

### Work inside a task

```bash
task check              # run project checks for the current task
task rebase [args…]     # rebase task branch onto a base ref
task coverage           # cargo-llvm-cov coverage for Rust tasks
```

`task check` and `task rebase` are used by the `rebase` skill.

## Exploring a repo's main branch (detach)

When you want to read a repo's default branch without creating a feature branch, use a **detached worktree**. It's a normal working tree pinned to `origin/HEAD` that you can `cd` into, grep, read, and update in place.

```bash
task detach add <host>/<group>/<repo>      # create or refresh the detached worktree
task detach update <host>/<group>/<repo>   # fetch + hard-reset to remote default
task detach list                           # show all detached worktrees with their commit
task detach remove <host>/<group>/<repo>
```

The worktree ends up at `~/dev/detached/<host>/<group>/<repo>/`. Treat it as read-only: `task detach update` will hard-reset it, so don't keep local edits there.

Typical use:

- Read unfamiliar upstream code before starting a task.
- Feed a repo into grep/search tools without a feature-branch checkout.
- Serve as the `cargo install --path` source for binary installs (below).

## Installing binaries (detach + TOML)

`task` installs Rust binaries directly from detached worktrees via `cargo install --path <path> --locked`. Entries are declared in TOML:

### Public base: `~/.config/task/config.toml`

```toml
repos_dir    = "~/dev/repos"
wt_dir       = "~/dev/wt"
detached_dir = "~/dev/detached"

[[install]]
repo = "github.com/tsauvajon/goto"

[[install]]
repo = "github.com/tsauvajon/task"

[[install]]
repo = "github.com/bahdotsh/mdterm"

[[install]]
repo = "github.com/jrobhoward/dumap"
```

### Private overlay: `~/.config/dotfiles/task.install.toml`

Holds machine-local `[[install]]` entries (not tracked in dotfiles). Same schema as the public base — `setup.sh` appends these onto the base.

### Entry schema

```toml
[[install]]
repo        = "<host>/<group>/<repo>"   # required; matches a detach target
path        = "crates/<crate-name>"      # optional; pick a specific crate in a workspace
extra_flags = ["--features", "foo,bar"]  # optional; forwarded to cargo install
```

- `repo` is the same identifier you pass to `task detach add`.
- `path` is needed for virtual workspaces where the bin crate isn't at the root. If omitted, `task` inspects the root manifest and picks the sole bin member, or the bin member whose package name matches the repo short name.
- `extra_flags` forwards arbitrary flags to `cargo install` (features, `--all-features`, etc.).

### Install commands

```bash
task detach install              # install every configured entry
task detach install <repo>       # install one entry
```

Each install runs `cargo install --path <detached-worktree>/<path> --locked`. To update a tool:

```bash
task detach update  <host>/<group>/<repo>
task detach install <host>/<group>/<repo>
```

This is the canonical way to install and update internal or fork-only CLIs — detach first, install from the detached worktree, no crates.io hop.

## Repo management

```bash
task repo clone <url> [repo_key]   # add a bare clone under ~/dev/repos
task repo list                     # list known repos
task repo prune                    # prune stale worktree metadata
```

`task start` and `task detach add` will clone on demand, so `task repo clone` is only needed when you want a bare clone without a worktree.

## Bootstrap & health

```bash
task bootstrap   # prepare workspace directories (run once; setup.sh calls it)
task doctor      # check toolchain/workspace health; can apply fixes
```

## Cookbook

Start a new feature task:

```bash
task start <host>/<group>/<repo> feat/<ticket>/<short-desc>
```

Read another repo's current `main`:

```bash
task detach add <host>/<group>/<repo>
cd ~/dev/detached/<host>/<group>/<repo>
```

Switch between in-flight tasks:

```bash
task park                          # leave the current one
task open <repo> <branch>          # attach to another
task list                          # if unsure what's open
```

Update and reinstall a tool managed via `[[install]]`:

```bash
task detach update  <host>/<group>/<repo>
task detach install <host>/<group>/<repo>
```

Jump into a task's directory from anywhere:

```bash
cd "$(task path <repo> <branch>)"
```

Remove a finished task worktree:

```bash
task finish <repo> <branch>
```

## References

- Base config: `config/task/config.toml` (symlinked to `~/.config/task/config.toml`).
- Private overlays: `~/.config/dotfiles/task.*.toml` (appended onto the base by `setup.sh`).
- Overlay-append mechanics: see the dotfiles repo `AGENTS.md` section "Overlay-append merges".
- Companion skills: `rebase` (uses `task rebase` / `task check`), `create-merge-request`.
