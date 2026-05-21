---
description: Implement a plan with parallel subagents, review loops, deferred decisions, and focused commits
---
Use the current conversation plan as the plan. Treat this input as additional context or constraints, not as a replacement plan: $ARGUMENTS. If no clear plan exists, ask for the plan before implementation.

Use subagents aggressively where they add value.

If the plan has independent implementation steps, spawn the most specific relevant subagent for each step in parallel. For Rust code changes, use `rust` after `rust-design` when design input is needed. Use `implement` only when no narrower specialist fits. Do not parallelize steps that touch the same files, depend on each other, or risk conflicting changes.

After each completed implementation step, dispatch two review subagents in parallel:
- one to review the implementation for bugs, regressions, missing tests, and code quality
- one to compare the implementation against the original plan and identify gaps or scope drift

Iterate implementation -> reviews -> obvious fixes until both reviews are clean or only non-obvious tradeoffs remain.

Prefer making reasonable local decisions without interrupting the user. Defer questions until the end unless a decision is blocking, risky to guess, or would cause significant rework. For deferred decisions, provide an executive summary with options, recommendation, and impact.

After each cleanly finished, reviewed, and verified step, commit only the relevant work. Inspect git status and diff before committing. Keep commits focused and do not include unrelated changes.
