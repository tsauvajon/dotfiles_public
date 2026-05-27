---
description: Execute a plan by parallelizing independent agent work, reviewing results, and making focused commits
---
Follow the current conversation plan. Extra context or constraints, if provided: $ARGUMENTS

Model the plan as a dependency graph. Continuously launch every ready workstream in parallel: no unfinished parent steps and no file/resource conflicts. When a workstream finishes, launch its code and plan reviews in parallel and verify it; once clean, immediately launch newly unblocked children.

For each workstream, use the most specific relevant agent. For Rust changes, use `rust-design` first when design is unclear, then `rust`; use `implement` only when no narrower specialist fits.

Reviews:
- code: bugs, regressions, missing tests, and quality
- plan: gaps, scope drift, and missed requirements

Within each workstream, iterate implementation -> review -> delegated fixes until reviews are clean or only explicit tradeoffs remain. Send fixes back to the owning workstream agent, or launch the most specific relevant agent for new fix work. The main agent coordinates, reviews, and verifies; it should not implement non-trivial fixes itself.

Make reasonable local decisions without interrupting the user. Ask immediately only when a decision is blocking, risky to guess, or would cause significant rework. For deferred questions, summarize options, recommendation, and impact.

After each cleanly finished, reviewed, and verified workstream, commit only the relevant work. Inspect git status and diff before committing. Keep commits focused and do not include unrelated changes.
