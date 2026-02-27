---
name: aggressive-testing
description: Maximize meaningful test coverage quickly by parallelizing across modules, refactoring aggressively for testability within module boundaries, and producing a structured coverage report.
compatibility: opencode
metadata:
  status: experimental
  version: "0.1.0"
---

# Aggressive Testing

Maximize meaningful test coverage quickly, prioritizing testability over preserving existing structure. Be willing to refactor aggressively (within module boundaries) when it unlocks better, maintainable tests.

## Prerequisites

- A project with identifiable top-level modules or packages
- Existing test runner available (e.g., `cargo test`, `pytest`, `jest`, `go test`)
- Clean git working tree before starting

## Step 0: Pre-flight Checks

1. Verify clean git state with `git status --porcelain`.
2. Identify the test runner and confirm tests currently pass.
3. Identify top-level modules/packages (e.g., `src/*`, `services/*`, `libs/*`, `apps/*`).

If the baseline test run fails, stop and report the failure before proceeding.

## Step 1: Plan Module Coverage

1. List all top-level modules and their file counts.
2. Rank files within each module by priority:
   1. High-churn/core business logic files
   2. Files with complex branching and no tests
   3. Utility/shared files that unlock many downstream tests
   4. Remaining files
3. Spawn one subagent per top-level module; each subagent owns its module end-to-end.

## Step 2: Per-Module Work (Run in Parallel per Module)

For each file in the module, iterate in priority order:

1. **Assess** current behavior and existing tests.
2. **Add/upgrade** tests where straightforward.
3. **If testing is difficult**, refactor decisively to improve seams, then test:
   - Split large files/functions
   - Extract testable units
   - Introduce interfaces/adapters for hard dependencies
   - Replace hidden/global state with explicit inputs
   - Remove dead code revealed during refactor

### Aggressive Refactor Policy

Allowed:
- Split large files/functions
- Extract testable units
- Introduce interfaces/adapters for hard dependencies
- Replace hidden/global state with explicit inputs
- Remove dead code revealed during refactor

Not allowed:
- Cross-module architecture rewrites
- New frameworks/tools unless already present in the project
- Behavior changes without tests proving intended behavior

### Timebox and Abort Rules

- Max 3 attempts per file.
- If blocked:
  - Revert ALL changes for that file (or small refactor batch) immediately.
  - Record the skip reason and a concrete next step.
  - Move on without debate.
- Do not spend extended time on edge-case-heavy files unless high-impact.

### Validation Discipline

- Run the nearest relevant tests after each successful file/refactor batch.
- Keep the branch green as often as practical.
- If a refactor destabilizes tests, roll back that batch immediately.

## Step 3: Per-Module Report

Each subagent must report in this format:

- **Files reviewed**: N
- **Tests added/updated**: [list]
- **Files refactored for testability**: [list + brief rationale]
- **Files reverted/skipped**: [list + reason + suggested follow-up]
- **Commands run**
- **Estimated confidence level**: high / med / low
- **Coverage delta**: exact if available, directional if not

## Step 4: Final Consolidated Summary

After all modules complete, produce:

- Consolidated cross-module summary
- Top 10 next files by ROI for more testing
- Explicit "reverted/skipped" ledger with reasons
- Short risk notes for any behavior-sensitive refactors

## Constraints

- Never use `--no-verify`
- Never leave the repo in a non-compiling state
- Never change behavior without tests proving the intended behavior
- Revert failed refactor batches immediately; do not leave partial changes
