Use specialist subagents aggressively for non-trivial work. The primary agent should delegate to at least one relevant specialist rather than doing everything inline.

**Routing guide — try named specialists first:**

- **`explore`** — local code discovery (finding files, symbols, call sites, config locations, understanding unfamiliar codebases). Do not run Cargo/build/test commands; return evidence for the primary agent to decide whether verification is needed.
- **`verify`** — noisy verification commands (cargo, nix, test, lint, build, or long shell output). Request a compact failure summary instead of consuming full logs directly.
- **`review`** — candidate review of diffs or implementations before committing or merging. Do not run Cargo/build/test commands; identify risks, missing tests, and whether a `verify` subagent should run checks.
- **`scout`** — external research (documentation, API docs, vendor docs, ecosystem research, dependency behavior checks, pricing/model lookup). The primary agent must not perform web research directly; always delegate to `scout`. If local context is needed for external research, use `explore` first or provide concrete paths/context to `scout`. Scout returns sources, verified facts, unknowns, and relevance to the local task.
- **`rust-design`** — Rust architecture and API/type design. Use for crate/module boundaries, trait design, error handling strategies, async/concurrency choices, ownership/lifetime implications, and migration plans. Read-only — does not edit files. Prefer `rust-design` in plan mode or before broad Rust changes when the design is unclear.
- **`rust`** — Rust implementation and coding. Use for Rust design plus implementation, refactoring, and applying idiomatic Rust conventions. For substantial Rust work, use `rust-design` first when design is unclear, then `rust`.
- **`implement`** — fallback implementation work when no narrower specialist fits (editing files, writing code, running verification). Do not use for Rust code changes; use `rust` instead. Preserve the codebase-study requirement: use `explore` first when context is unclear or when similar patterns need to be found before delegating to `implement`. The primary agent reviews the result and decides whether to commit.
- **`general`** — fallback for work that does not fit any specialist. Try named specialists first; use `general` only when no named specialist is a good match.

**Parallel dispatch is the default for independent subagent work.** Launch independent `explore`, `scout`, `review`, `verify`, `rust-design`, `rust`, `implement`, or `general` subagents in parallel whenever their tasks do not depend on each other's output. Only serialize when one subagent's result is needed before starting another.

Keep final decisions with the primary agent.
