---
name: pr
description: Prepare and open a GitHub pull request with gh using minimal reviewer-focused text.
compatibility: opencode
metadata:
  status: experimental
  version: "0.1.3"
---

# Open GitHub Pull Request

Create a high-quality pull request from the current branch using `gh`.

## Prerequisites

- Run in a git repository with a checked-out feature branch
- `gh` is installed and authenticated
- Changes are committed locally

## Step 0: Pre-flight Checks

1. Run `git status --short --branch`.
2. Identify current branch with `git rev-parse --abbrev-ref HEAD`.
3. Resolve base branch in a single command (unless user specifies one), and carry a single `<base_ref>` through the workflow:

```bash
BASE_REF="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"; if [ -n "$BASE_REF" ]; then BASE_REF="$BASE_REF"; elif git show-ref --verify --quiet refs/remotes/origin/master; then BASE_REF="origin/master"; elif git show-ref --verify --quiet refs/remotes/origin/main; then BASE_REF="origin/main"; elif git show-ref --verify --quiet refs/heads/master; then BASE_REF="master"; else BASE_REF="main"; fi; echo "$BASE_REF"
```
4. Verify remote tracking and push status with `git branch -vv`.

If current branch is `main` or `master`, stop and ask for a feature branch name.

## Step 1: Review PR Content

1. Get commits to include with `git log --oneline <base_ref>..HEAD`.
2. Review code delta with `git diff --stat <base_ref>...HEAD`.
3. Capture key purpose, notable implementation details, and any risks.
4. Scope sanity check: if the commit list or diffstat appears unexpectedly large for the user's request, stop and re-check `<base_ref>` before continuing.

## Step 2: Rust Validation (Rust PRs Only)

If the repository is Rust-based (for example contains `Cargo.toml`), run validation before opening the PR in this order:

1. Prefer project workflow checks first:

```bash
task check
```

2. If `task check` is unavailable, use project shell tooling if available (for example Nix):

```bash
nix develop -c cargo fmt
nix develop -c cargo clippy --workspace --all-targets --all-features -- -D warnings -D rust-2024-compatibility -A deprecated
nix develop -c cargo test
```

3. Otherwise use local cargo:

```bash
cargo fmt
cargo clippy --workspace --all-targets --all-features -- -D warnings -D rust-2024-compatibility -A deprecated
cargo test
```

If any command fails, stop and report the failure instead of creating the PR.

## Step 3: Push Branch If Needed

Push branch explicitly (do not rely on local upstream state):

```bash
git push -u origin "$(git rev-parse --abbrev-ref HEAD)"
```

Then derive repo owner for explicit PR head:

```bash
OWNER="$(gh repo view --json owner --jq '.owner.login')"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
```

## Step 4: Draft Title and Description

Build a concise PR title from commit intent.

Description policy (strict):

1. Keep it as small as possible.
2. If code changes + title already explain the PR, use no description.
3. Add description only for information not evident from the code (for example: intent, constraints, rollout context, or external reasoning).
4. Prefer 1-3 short bullet points when description is needed.
5. Shell safety: do not use Markdown backticks in PR body text. Use plain text only.

## Step 5: Create Pull Request

Create the PR with `gh pr create`.

Always pass `--head` and `--body` in non-interactive mode.
When setting the body, always use a single-quoted HEREDOC and plain text bullets.
Do not place backticks in the body text.

```bash
# If additional context is needed
gh pr create --base <base_ref> --head "<owner>:<branch>" --title "<title>" --body "$(cat <<'EOF'
- Brief non-obvious intent
- Important constraint for reviewers
EOF
)"

# If no extra context is needed
gh pr create --base <base_ref> --head "<owner>:<branch>" --title "<title>" --body ""
```

If `gh` reports that the branch is not pushed, run the push command above and retry once.

If the repo has a PR template, keep only fields that add non-obvious context and remove boilerplate text.

## Step 6: Report Result

Return:

- PR URL
- Base and head branches
- Whether a description was added, and why
- Any follow-up actions

## Constraints

- Never use `--no-verify` or force push unless the user explicitly asks
- Do not create or modify commits unless asked
- Keep PR description factual and reviewer-friendly
