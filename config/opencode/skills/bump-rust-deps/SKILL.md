---
name: bump-rust-deps
description: Bump Rust dependencies one by one, verify compile and clippy after each, and commit each successful bump separately.
compatibility: opencode
metadata:
  status: experimental
  version: "0.1.0"
---

# Bump Rust Dependencies

Bump Rust crate dependencies one at a time, verifying each bump compiles and passes clippy before committing.

## Prerequisites

- Rust project with `Cargo.toml` in the current directory or workspace root
- `cargo` and `clippy` available
- Clean git working tree before starting

## Step 0: Pre-flight Checks

1. Verify clean git state with `git status --porcelain`.
2. Verify the project compiles with `cargo check`.
3. Verify clippy passes with `cargo clippy --all-targets --all-features -- -D warnings`.
4. Detect workspace mode by checking root `Cargo.toml` for `[workspace]`.

If `cargo check` fails, stop and report the baseline failure.

## Step 1: Gather Outdated Dependencies

Run `cargo outdated --root-deps-only --depth 1`.

If `cargo-outdated` is missing, fall back to `cargo update --dry-run`.

Default behavior: attempt all direct outdated dependencies unless the user asks to skip specific crates.

## Step 2: Plan Bump Order

Order by risk:

1. Patch bumps first
2. Minor bumps second
3. Major bumps last

## Step 3: Bump Loop

For each dependency:

1. Update version requirement in `Cargo.toml` (or `[workspace.dependencies]` in workspace root).
2. Run `cargo update -p <crate>`.
3. Run `cargo check --all-targets --all-features`.
4. Run `cargo clippy --all-targets --all-features -- -D warnings`.

If clippy fails, attempt minimal compatibility fixes and rerun checks.

If the bump still fails after up to 3 attempts:

- Try an intermediate major version when appropriate.
- If still failing, revert only files changed for that dependency bump and skip it.
- Report the short failure reason.

## Step 4: Commit Each Successful Bump

For each successful bump:

```bash
git add -A
git commit -m "chore: bump <crate> from <old> to <new>"
```

If code changes were needed beyond lock/manifest changes, include a short second commit-message paragraph describing the adaptation.

## Step 5: Final Verification

After processing all dependencies:

1. `cargo test --all-targets --all-features`
2. `cargo clippy --all-targets --all-features -- -D warnings`

## Step 6: Summary

Provide:

- Bumped crates with old -> new versions
- Skipped crates with short reasons
- Total number of commits

## Constraints

- One dependency per commit
- Never use `--no-verify`
- Never leave the repo in a non-compiling state
- Keep code changes minimal and directly tied to the bump
- Respect project style and existing patterns
