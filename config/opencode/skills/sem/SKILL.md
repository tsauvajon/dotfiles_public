---
name: sem
description: Use sem for semantic Git analysis: entity-level diffs, blame, history, impact, and focused code context before editing, reviewing, or committing code.
---

# sem

`sem` is semantic version control on top of Git. Use it to inspect code changes at the function, method, class, or module level instead of relying only on line diffs.

## When To Use

- Use `sem diff` before reviewing or summarizing code changes.
- Use `sem diff --staged` before committing staged changes.
- Use `sem entities <path>` when you need to discover the semantic units in an unfamiliar file or directory.
- Use `sem impact <entity>` before changing shared functions, public APIs, or code with unclear dependencies.
- Use `sem blame <file>` and `sem log <entity>` when investigating why an entity changed.
- Use `sem context <entity> --budget <tokens>` when you need focused context for an LLM-sized prompt.

## Workflow

Start with the current change set:

```sh
sem diff --format json
```

For commit preparation, inspect what is actually staged:

```sh
sem diff --staged --format json
```

When the touched area is unclear, list entities first and then drill into the relevant one:

```sh
sem entities src/
sem impact path/to/file.rs::entity_name
sem context path/to/file.rs::entity_name --budget 4000
```

For history and ownership questions, prefer entity-level commands before broad Git archaeology:

```sh
sem blame path/to/file.rs
sem log path/to/file.rs::entity_name --limit 10
```

## Agent Guidance

- Prefer JSON output when `sem` supports it, because it is easier to inspect and summarize accurately.
- Treat `sem` as an analysis aid, not as a replacement for `git diff`, tests, typechecks, or builds.
- Use `sem impact` before edits that could affect callers or tests across files.
- Use `sem context` to keep code-reading focused instead of dumping entire files into the conversation.
- Mention any uncertainty if `sem` cannot parse a language or entity shape correctly.

## Constraints

- Do not run `sem setup` or `sem unsetup` unless the user explicitly asks; those commands mutate repository Git configuration or hooks.
- Do not configure or rely on the `sem` MCP server for this dotfiles setup.
- If `sem` conflicts with GNU Parallel's `sem`, verify `sem --version` reports Ataraxy `sem` before trusting results.
