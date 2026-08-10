---
description: Execute the approved plan with dependency-aware parallel implementation and integrated validation
---
Follow the current conversation plan. Extra context or constraints, if provided: $ARGUMENTS

Build a dependency DAG. Group work that shares files, APIs, or strong dependencies into one owning workstream. Launch genuinely independent ready work in parallel, with at most three concurrent implementation agents by default; use another limit only when the arguments justify it. Use the most specific relevant agent, retain each task ID, and resume owning tasks for fixes. Use `rust-design` only for unresolved Rust design.

Before implementation, request at most one plan/design review, and only when security, data/migration, public-API, broad-architecture risk, or material uncertainty warrants it. Skip it for clear, approved plans. Do not run per-workstream reviews, verification, or commits. Explicitly instruct `implement` and `rust-implement` tasks that verification is deferred to integrated preflight/CI.

After all implementation completes, run one integrated fast preflight: any formatter/normalizer declared by repository docs, config, or hooks, then only repository-defined, known-fast affected compile/typecheck/lint/targeted tests. Skip undeclared checks instead of discovering commands by trial and error; CI owns broad validation. Keep hooks enabled.

Inspect status and diff, then commit only intended work: one focused commit per coherent iteration, excluding unrelated changes. Push and create an MR through the repository's normal workflow.

After pushing and creating the MR, capture the commit SHA and merge base, then launch in parallel exactly one `review` task and one `bash-runner` CI watcher. Give both the SHA and complete delegation context. Review only the immutable committed diff ending at that SHA, never the working tree, for bugs, regressions, missing tests, quality, plan conformance, and scope drift. Give the watcher an exact provider-native status command with a fixed poll interval and hard timeout; a timeout is unresolved, not a reason to keep polling. Wait for both, validate and deduplicate findings, then send one combined fix batch by resuming the owning implementation task(s) and explicitly restating that verification remains deferred. For failed GitLab CI, use `fix-failing-ci-pipeline` for diagnosis only; do not make independent edits, commits, or pushes.

After code fixes, run the fast preflight once, commit and push, then resume the focused review and watch CI for the new SHA. Do not re-review transient CI retries with an unchanged SHA. Cap total fix-and-repush iterations at three regardless of whether CI, review, or both remain unresolved; then escalate with the outstanding findings and tradeoffs. Missing CI is unresolved, not success. Complete only with successful CI and a clean review, or explicit accepted tradeoffs.

Make reasonable local decisions without interrupting the user. Ask only when a decision is blocking, risky to guess, or would cause significant rework; otherwise report deferred questions with options, recommendation, and impact.
