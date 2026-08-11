---
description: Execute the approved plan with dependency-aware parallel implementation and integrated validation
---
Follow the current conversation plan. Extra context or constraints, if provided: $ARGUMENTS

Build a dependency DAG. Group work that shares files, APIs, or strong dependencies into one owning workstream. Maximize safe parallelism: launch every ready, non-conflicting subagent as soon as its inputs are available. Use the most specific relevant agent, retain each task ID, and resume owning tasks for fixes. Use `rust-design` only for unresolved Rust design.

Before implementation, use plan/design review(s) when complexity, risk, ambiguity, or independent specialist domains materially benefit; skip redundant reviews for clear, approved plans. Do not run routine per-workstream reviews, verification, or commits. Explicitly instruct `implement` and `rust-implement` tasks that verification is deferred to integrated preflight/CI.

After all implementation completes, run one integrated fast preflight: prefer formatters/normalizers and fast checks declared by repository docs, config, or hooks, then only repository-defined, known-fast affected compile/typecheck/lint/targeted tests. If none are declared, infer the ecosystem and use well-known fast defaults (for example, `cargo fmt` for Rust). Avoid broad suites and trial-and-error; CI owns broad validation. Keep hooks enabled.

Inspect status and diff, then commit only intended work: one focused commit per coherent iteration, excluding unrelated changes. Push and create an MR through the repository's normal workflow.

After pushing and creating the MR, capture the immutable commit SHA and merge base, then launch final integrated review work and watch CI in parallel. Review only the immutable committed diff ending at that SHA, never the working tree, for bugs, regressions, missing tests, quality, plan conformance, and scope drift. Wait for review and CI, then validate and deduplicate findings. If CI is red, ensure the CI investigation returns each exact failed command. Send one combined fix batch by resuming the owning implementation task(s) and explicitly restating that verification remains deferred.

After code fixes, run the fast preflight once. When CI was red, delegate each exact failed command verbatim to `bash-runner` and require it to pass locally before pushing; if a command cannot be reproduced locally, keep it unresolved and do not claim success. Commit and push, then resume final review and watch CI for the new SHA. Do not re-review transient CI retries with an unchanged SHA. Cap total fix-and-repush iterations at three regardless of whether CI, review, or both remain unresolved; then escalate with the outstanding findings and tradeoffs. Missing CI is unresolved, not success. Complete only with successful CI and clean review, or explicit accepted tradeoffs.

Make reasonable local decisions without interrupting the user. Ask only when a decision is blocking, risky to guess, or would cause significant rework; otherwise report deferred questions with options, recommendation, and impact.
