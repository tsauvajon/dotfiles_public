---
name: allow-opencode-commands
description: Whitelist bash command permission patterns in this dotfiles OpenCode config.
compatibility: opencode
metadata:
  status: experimental
  version: "0.4.0"
---

# Allow OpenCode Commands

Use this skill to add safe bash permission patterns to the canonical public OpenCode permission fragment in this repo.

## Modes

- Direct mode: when the user provides one or more permission patterns such as `just *` or `MYVAR=*`, add them after checking duplicates and broadening risk.
- Scan mode: when no pattern is provided, inspect recent OpenCode session history for repeated unapproved commands, present candidates, and add only the user's selections.

## Wildcard Rules

- OpenCode `*` matches across spaces.
- A trailing ` *` also matches no-argument invocation, so `ls *` matches `ls` and `ls -la`.
- Permission evaluation is last-match-wins. Keep broad rules before specific denies.
- Prefer specific multi-subcommand patterns such as `git status *` over broad `git *` unless the user explicitly wants broad coverage.

## Workflow

1. Find the public `config/opencode/opencode.*.json` fragment that owns `permission.bash`; do not create a bare `opencode.json`.
2. Check exact duplicates, covered patterns, and risky broadening.
3. Add new `allow` entries in sorted order while preserving all existing entries and deny rules.
4. Run `bash setup.sh` from this repo.
5. Report added, skipped, and already-covered patterns.

## Constraints

- Never edit generated `~/.config/opencode/opencode.json` directly.
- Never remove existing permission entries.
- Never whitelist commands the user explicitly skips.
- Do not echo secrets found in session history.
