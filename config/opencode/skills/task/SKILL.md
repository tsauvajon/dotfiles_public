---
name: task
description: Use `task` for repo/worktree/detach workflows — creating feature tasks and exploring a repo's main branch via detached worktrees.
compatibility: opencode
---

# task workflow

`task` is a Rust workflow helper (`github.com/tsauvajon/task`) that manages three things:

1. **Bare clones** of repos, stored under `~/dev/repos/`.
2. **Detached worktrees** pinned to each repo's default branch, stored under `~/dev/detached/`. Used for reading `main`/`master` without creating a feature task.
3. **Task worktrees** (one per feature branch) stored under `~/dev/wt/`. Each task gets its own directory and zellij session.

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
- `~/.config/dotfiles/task.*.toml` — private overlays (machine-local, not tracked). Merged into the generated config by Home Manager.

The base config defines `repos_dir`, `wt_dir`, `detached_dir`, and `editor`.

## Task worktrees (feature work)

### Create / open a task

```bash
task start <host>/<group>/<repo> <branch> [base_ref]
```

- Clones the repo into `~/dev/repos/` if needed.
- Creates a new worktree under `~/dev/wt/<host>/<group>/<repo>/<branch>/`.
- Opens zellij, opencode, and vscodium in the new worktree.
- Add `--no-open` to skip opening tools.

Example (generic):

```bash
task start <host>/<group>/<repo> feat/<ticket>/<short-desc>
```

### Park, re-open, finish

```bash
task park                            # stop the current task's zellij session (worktree stays)
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
- Keep a stable checkout of a repo's default branch for comparison and reference.

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

Refresh a detached worktree:

```bash
task detach update <host>/<group>/<repo>
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
- Private overlays: `~/.config/dotfiles/task.*.toml` (merged into the generated config by Home Manager).
- Overlay-append mechanics: see the dotfiles repo `AGENTS.md` section "Overlay-append merges".
- Companion skills: `rebase` (uses `task rebase` / `task check`).
