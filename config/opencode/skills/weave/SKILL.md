---
name: weave
description: Use Weave for Git merge/rebase conflict reduction, semantic merge previews, and local merge-driver setup.
compatibility: opencode
metadata:
  status: experimental
  version: "0.1.0"
---

# Weave

Use Weave to reduce Git merge and rebase conflicts with an entity-aware merge driver. Treat it as conflict assistance, not correctness proof: always inspect the resulting diff and run project validation.

## When To Use

- Use before or during conflict-heavy `git merge`, `git rebase`, or `git pull` work.
- Use when changes touch supported source or structured data files, especially Rust, TypeScript, JavaScript, Python, Go, JSON, YAML, TOML, Markdown, and similar text formats.
- Use `weave preview <branch>` before risky merges to estimate whether Weave can resolve conflicts cleanly.
- Do not use as a substitute for understanding both sides of a conflict.

## Setup Preference

Prefer local setup unless the user explicitly wants a team-wide repository configuration:

```bash
weave setup --local
```

Local setup writes Git merge-driver config to `.git/config` and Weave attributes to `.git/info/attributes`. These files are local to the repository checkout and are not committed.

Only use repository setup when the team wants tracked `.gitattributes` entries:

```bash
weave setup
```

Do not run `weave unsetup` casually. It removes the Weave merge-driver config and strips `merge=weave` entries from both `.git/info/attributes` and tracked `.gitattributes`.

## Checks

Check installation:

```bash
command -v weave
weave --help
```

Check whether the current repository is configured:

```bash
git config --get merge.weave.driver
git check-attr merge -- path/to/file
```

`git check-attr` should report `merge: weave` for files covered by the active attributes.

## Preview Workflow

Preview a merge before modifying the working tree:

```bash
weave preview <branch>
```

Use preview output as advisory. For rebases, remember that Git replays commits one at a time, so a single preview against the base branch is only a risk signal, not a complete simulation of every rebase step.

## Merge And Rebase Workflow

After setup, normal Git commands invoke Weave automatically for files matched by the configured attributes:

```bash
git merge <branch>
git rebase <branch>
git pull --rebase
```

If conflicts remain:

1. List conflicted files with `git status --short`.
2. Inspect base, ours, and theirs with `git show :1:<file>`, `git show :2:<file>`, and `git show :3:<file>`.
3. Resolve by preserving behavior and project invariants.
4. Stage resolved files with `git add <file>`.
5. Continue the Git operation with `git rebase --continue` or complete the merge normally.

## Validation

After any Weave-assisted operation:

1. Review `git diff` and `git diff --staged` for unintended behavior changes.
2. Run focused tests for touched areas.
3. Run the repository's normal full validation before reporting success.
4. Report whether Weave was configured locally, whether it auto-resolved conflicts, and which files still required manual resolution.

## Constraints

- Never assume Weave output is semantically correct without review.
- Never commit `.gitattributes` changes from `weave setup` unless the user explicitly asked for repository-wide Weave configuration.
- Prefer `weave setup --local` for agent-assisted work.
- Do not run `weave unsetup` unless the user asks to remove Weave or the local setup is known to be temporary and safe to clean up.
