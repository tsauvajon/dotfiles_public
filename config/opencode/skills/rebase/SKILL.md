---
name: rebase
description: Rebase safely with deep conflict resolution, run checks, and verify no unintended changes against default branch.
compatibility: opencode
metadata:
  status: experimental
  version: "0.3.0"
---

# Safe Rebase

Rebase the current branch with deliberate conflict resolution, validation, and a final correctness pass against the default branch.

## Prerequisites

- Run inside a git repository on a feature branch (not `main`/`master`)
- `task` is available and supports `task rebase` and `task check`
- Working tree is clean before rebasing (create a meaningful safeguard commit first if needed)

## Step 0: Pre-flight, Clean Tree, and Baseline Capture

1. Record branch name with `git rev-parse --abbrev-ref HEAD`.
2. If the current branch is `main` or `master`, stop and ask for a feature branch.
3. Check working tree with `git status --porcelain --branch`.
4. If the working tree is not clean (staged, unstaged, or untracked changes), create a meaningful safeguard commit before rebasing:
   - Stage all changes with `git add -A`.
   - Commit with a normal descriptive message that explains the actual work, no indication it's a safeguard commit.
   - Example: `feat: rename opencode sessions on park`.
   - Do not start rebase until this commit succeeds.
5. Determine default branch using `origin/HEAD`, fallback `master`, then `main`.
6. Capture pre-rebase baseline:
   - `OLD_HEAD="$(git rev-parse HEAD)"`
   - `BASE="<resolved default branch>"`
   - `OLD_MERGE_BASE="$(git merge-base HEAD "$BASE")"`
   - `git log --oneline "$OLD_MERGE_BASE"..HEAD`
   - `git diff --stat "$OLD_MERGE_BASE"...HEAD`

## Step 1: Run Rebase Task

Run:

```bash
task rebase
```

If no conflicts occur, continue to Step 3.

## Step 2: Resolve Conflicts Deeply (When Needed)

For each conflicted file:

1. List conflicts with `git status --short`.
2. Understand intent before editing:
   - Read common ancestor (`:1:`), current branch (`:2:`), and incoming branch (`:3:`).
   - Use explicit views when needed:
     - `git show :1:<file>`
     - `git show :2:<file>`
     - `git show :3:<file>`
   - Review surrounding commits from both sides to understand why each change exists.
3. Resolve by preserving behavior and invariants, not just removing markers.
4. Check for unintended deletions, duplicated logic, silent behavior changes, and API/contract drift.
   - If conflicts involve version fields (for example `Cargo.toml`), keep the single intended semantic version bump for the branch and avoid duplicate or accidental rollback bumps.
5. Stage resolved file with `git add <file>`.

After resolving a conflict batch, run focused validation relevant to touched areas when possible. Then continue rebase with:

```bash
git rebase --continue
```

If the continue step fails because the editor requires an interactive TTY, use:

```bash
GIT_EDITOR=true git rebase --continue
```

Repeat until the rebase completes.

## Step 3: Normalize Formatting

Before full validation, normalize formatting for touched files using project tooling:

1. Prefer `task fmt` if available in the repository.
2. Otherwise use project shell tooling (`nix develop -c cargo fmt`) when applicable.
3. Fallback to `cargo fmt`.

Then stage any formatting-only updates produced during conflict resolution.

## Step 4: Run Full Validation

Run:

```bash
task check
```

If `task check` fails, fix issues and rerun until it passes.

## Step 5: Clean Tree Gate

After validation passes, verify the tree is clean:

```bash
git status --porcelain
```

If output is non-empty:

1. Confirm whether remaining changes are expected generated updates (for example lockfile/version alignment).
2. Run one formatting/normalization pass again if needed, then rerun `task check`.
3. Re-check cleanliness.
4. If still dirty, report exact files and classify risk (expected/generated vs potentially unintended behavior changes).

## Step 6: Final Pass Against Default Branch

1. Recompute base after rebase:
   - `NEW_HEAD="$(git rev-parse HEAD)"`
   - `NEW_MERGE_BASE="$(git merge-base HEAD "$BASE")"`
2. Compare old vs new commit series for unintended semantic drift:
   - `git range-diff "$OLD_MERGE_BASE".."$OLD_HEAD" "$NEW_MERGE_BASE".."$NEW_HEAD"`
3. Review final branch delta against default branch:
   - `git log --oneline "$NEW_MERGE_BASE"..HEAD`
   - `git diff --stat "$NEW_MERGE_BASE"...HEAD`
   - `git diff "$NEW_MERGE_BASE"...HEAD`
4. Investigate any unexpected changes and correct them before finishing.

## Step 7: Report Results

Return:

- Rebase outcome (success/failure)
- Whether conflicts occurred and how they were resolved
- Whether non-interactive editor fallback (`GIT_EDITOR=true`) was required
- Whether formatting produced follow-up changes after conflict resolution
- `task check` result
- Final verification notes from range-diff and base-branch diff
- Final working tree cleanliness status
- Any remaining risks or follow-up actions

## Constraints

- Never use `--no-verify`
- Never force push as part of this skill
- Never drop commits unless explicitly requested
- Prefer precise, minimal conflict resolutions aligned with existing project patterns
