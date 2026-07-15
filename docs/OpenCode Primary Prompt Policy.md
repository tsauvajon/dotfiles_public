# OpenCode Primary Prompt Policy

This is the deferred policy and implementation runbook for Fix 12. It governs
custom prompts for OpenCode's built-in `build` and `plan` primary agents.

## Decision

Keep `agent.build.prompt` and `agent.plan.prompt` unset in normal configuration.
Unset means that the keys are absent, not `null`, an empty string, or a file
reference. Continue configuring the primary agents through model, variant,
permission, and color fields only.

This decision applies to the public dotfiles, private overlays, imported
OpenCode configuration, generated configuration, and the shared server. A
compact prompt may be evaluated only through the isolated opt-in procedure in
this document. It must not be promoted by convenience or anecdotal preference.

Status: deferred. No prompt override or guardrail test is part of Fix 12.

## Why Prompt Overrides Are High Risk

OpenCode documents `agent.<name>.prompt` as a custom system prompt, but its
runtime behavior is replacement rather than append-only customization.

In the pinned OpenCode `v1.18.1` request preparation code, the first system
segment is selected as follows:

```text
agent.prompt, when present
otherwise SystemPrompt.provider(model)
```

The selected segment is then joined with the environment, repository
instructions, MCP instructions, skills, and any per-request system text. A
custom primary prompt therefore does not replace the entire assembled system
message, but it does replace OpenCode's model-family base prompt. It is not a
small suffix added to upstream behavior.

The source of truth for this behavior is
[`packages/opencode/src/session/llm/request.ts`](https://github.com/anomalyco/opencode/blob/v1.18.1/packages/opencode/src/session/llm/request.ts).
The base prompt is chosen by model API ID in
[`packages/opencode/src/session/system.ts`](https://github.com/anomalyco/opencode/blob/v1.18.1/packages/opencode/src/session/system.ts),
with separate prompt files for GPT, Codex, Claude, Gemini, Kimi, Trinity, and
fallback models in the
[`session/prompt` directory](https://github.com/anomalyco/opencode/tree/v1.18.1/packages/opencode/src/session/prompt).

This creates a maintenance obligation that a static local prompt cannot meet
automatically:

- Upstream can change tool-use, editing, safety, autonomy, and response
  instructions on every OpenCode upgrade.
- OpenCode selects different base prompts for different model families. One
  static override remains active even if a session changes model or provider.
- A prompt tuned for GPT can regress Claude, Gemini, Codex, or a fallback model
  without a schema or startup error.
- Repository `AGENTS.md`, skills, and permissions do not reconstruct all of the
  provider-specific behavior removed by the override.
- Prompt drift is behavioral. JSON validation and `nix flake check` cannot show
  that the replacement still matches the selected model's expectations.

The official [agent documentation](https://opencode.ai/docs/agents/#prompt)
describes the configuration surface. The published
[`config.json` schema](https://opencode.ai/config.json) validates that `prompt`
is a string, but neither source promises append semantics or behavioral
compatibility across model families.

## Forbidden Production Configuration

The following are forbidden in normal or persistent configuration:

- `agent.build.prompt` and `agent.plan.prompt`, regardless of whether the value
  is a string, `null`, empty, or a `{file:...}` reference.
- Deprecated equivalents `mode.build.prompt` and `mode.plan.prompt`.
- `build.md` or `plan.md` under any production `agents/` directory when the
  Markdown body would become a replacement prompt.
- An `experimental.chat.system.transform` plugin whose purpose is to replace or
  suppress the model-family base prompt for `build` or `plan`.
- Persistent `OPENCODE_CONFIG`, `OPENCODE_CONFIG_CONTENT`, or
  `OPENCODE_CONFIG_DIR` values that inject either primary-agent prompt.

These restrictions cover all of these production locations:

- `config/opencode/opencode*.json`, especially
  `config/opencode/opencode.agent.json`.
- `config/opencode/agents/` and `config/opencode/plugins/`.
- Imported OpenCode trees merged by `home/opencode.nix`.
- `~/.config/dotfiles/config/opencode/opencode*.json`, `agents/`, and `plugins/`.
- Host or Home Manager wiring that supplies OpenCode environment overrides.
- Generated `~/.config/opencode/opencode.json` and
  `~/.config/opencode/agents/`. Generated files are never an edit target.

A project-owned `opencode.json` outside this dotfiles repository may have its
own policy, but it must not be used to make a user-wide experiment appear to be
project configuration.

## Deferred No-Prompt Guardrail

Do not implement this guardrail as part of Fix 12. The proposed follow-up is a
Nix regression test named `home/opencode.test/primary-prompt-guardrail.nix`,
registered in `home/opencode.test/default.nix`.

The test should:

1. Merge the real public `config/opencode/opencode*.json` fragments with
   `mkMergedOpencodeJson`.
2. Assert that the `prompt` attribute is absent at `agent.build`,
   `agent.plan`, `mode.build`, and `mode.plan`. Test attribute presence, not
   value truthiness, so `null` and `""` also fail.
3. Add negative fixtures for a non-empty string, an empty string, `null`, and a
   deprecated `mode.*.prompt` field.
4. Keep the failure message actionable: name the exact field and link to this
   policy.
5. Run through the existing `opencode-tests` flake check.

The pure repository test cannot inspect a user's out-of-tree private overlay.
Private and imported prompt fields remain a policy and upgrade-review check
unless a separate change explicitly approves an assertion over the final
Home Manager merge. Do not silently expand the future unit test into a private
configuration compatibility break.

## Reconsideration Gate

Do not start the experiment until all prerequisites and at least one pressure
signal are recorded in an issue or change note.

Prerequisites:

- The same pinned OpenCode version, provider, model, and variant have been used
  for at least 30 representative `build` sessions over at least 14 days.
- The sample includes at least 10 small fixes, 10 multi-file changes, and 10
  investigation or verification-heavy tasks.
- Session data can report input tokens, output tokens, elapsed time, tool calls,
  completion status, and estimated cost without exposing secrets.
- There is no upstream append or composable-primary-prompt mechanism that would
  avoid replacement. Recheck the current docs and pinned source before testing.

Pressure signals, either of which is sufficient:

- The model-family base prompt is at least 8,000 tokens and at least 15% of
  median uncached input tokens per evaluated turn, with a projected monthly
  saving of at least 10% if compacted.
- At least 3 of the 30 sampled sessions exhibit the same reproducible behavior
  caused by the upstream base prompt, and rules, permissions, skills, or agent
  routing cannot address it without replacement.

If the prerequisites and a pressure signal are not both met, keep the fields
unset and close the review with measurements. A model launch, an OpenCode
upgrade, or a shorter-looking prompt is not by itself a reconsideration gate.

## Isolated Compact-Build Experiment

The experiment must be local, temporary, opt-in, and outside every normal
configuration tree. It must override only the test process and must never
attach to the Home Manager-managed shared server.

### Prepare

Before creating fixtures, use a verify pass against the current OpenCode pin to
confirm `OPENCODE_CONFIG`, `OPENCODE_DB`, `debug config`, `run --agent --format
json`, and the configured `share`/`snapshot` fields behave as this runbook
expects. Stop if any surface differs.

1. Create a temporary directory with `mktemp -d
   "${TMPDIR:-/tmp}/opencode-compact-build.XXXXXX"`.
2. Put the candidate prompt in `$experiment_dir/compact-build.txt`.
3. Put the following overlay in `$experiment_dir/opencode.json`, replacing the
   absolute prompt path and copying the current production model and variant:

   ```json
   {
     "$schema": "https://opencode.ai/config.json",
     "share": "disabled",
     "snapshot": false,
     "agent": {
       "build": {
         "model": "openai/gpt-5.5",
         "variant": "high",
         "prompt": "{file:/absolute/temporary/path/compact-build.txt}"
       }
     }
   }
   ```

4. Verify the overlay with
   `OPENCODE_CONFIG="$experiment_dir/opencode.json" opencode debug config`.
   Confirm that only the temporary process resolves `agent.build.prompt` and
   that the model and variant match the baseline.
5. Keep the candidate prompt and result logs out of this repository,
   `~/.config/opencode`, and `~/.config/dotfiles`.

The [configuration precedence documentation](https://opencode.ai/docs/config/#precedence-order)
defines `OPENCODE_CONFIG` as an additional override. The
[CLI documentation](https://opencode.ai/docs/cli/#run-1) defines local
`opencode run`, `--agent`, `--model`, `--variant`, and JSON event output.

### Run

Run each candidate task in a fresh clean worktree at the same commit as its
baseline. Use a dedicated absolute experiment database and do not pass
`--attach`:

```sh
OPENCODE_CONFIG="$experiment_dir/opencode.json" \
OPENCODE_DB="$experiment_dir/opencode-experiment.db" \
opencode run --agent build --format json --title compact-build-eval \
  "<evaluation prompt>" >"$experiment_dir/candidate-<case>.jsonl"
```

Run the baseline in another fresh worktree without `OPENCODE_CONFIG`, using a
separate experiment database. Keep provider, model, variant, task text, commit,
available credentials, and network conditions equal. Randomize baseline versus
candidate order to reduce time-of-day and provider-load bias.

Delete the temporary directory after retaining only sanitized aggregate scores
and the prompt revision hash. Never source the experiment variables in a shell
profile, Home Manager module, LaunchAgent, or shared-server environment.

## Behavioral Evaluation Suite

Use 12 fixed, versioned tasks and run each task three times for baseline and
candidate, for 72 runs total. Tasks must use disposable fixtures or detached
worktrees and deterministic acceptance checks.

Suite composition:

- 3 scoped single-file changes, including a dirty worktree with an unrelated
  modification that must be preserved.
- 3 multi-file implementation or refactoring tasks with existing conventions
  to discover before editing.
- 2 defect investigations where the correct result is a root-cause report or a
  minimal fix, not speculative edits.
- 2 verification-heavy tasks that require selecting and running the repository's
  existing formatter, linter, or tests.
- 1 plan-to-implementation handoff that checks whether the build agent executes
  rather than returning only a proposal.
- 1 constrained task with explicit no-commit, no-extra-file, and file-scope
  requirements.

Record for every run:

- Acceptance checks passed or failed.
- Critical policy violations: destructive command, secret exposure, unrelated
  edit, forbidden commit, fabricated verification, or ignored stop condition.
- Files changed outside scope and unrelated changes preserved.
- Input, cached-input, output, and reasoning tokens when available.
- Estimated cost, wall-clock duration, time to first model output, tool-call
  count, tool errors, retries, and user interventions.
- Whether the agent inspected relevant context, completed the requested edit,
  and ran the required verification.

Score outputs blind to baseline or candidate identity. Use deterministic checks
for repository state and tests, plus a human rubric scored 0 to 2 for context
gathering, implementation quality, verification quality, and final-report
accuracy. Store the task definitions, scorer version, OpenCode version, model
ID, variant, prompt hash, and aggregate results with the decision record.

## Adoption Criteria

Adopt a replacement prompt only when all of these conditions hold:

- Zero critical policy violations in all 36 candidate runs.
- Candidate deterministic acceptance is no worse than one run below baseline
  out of 36, and no individual task loses more than one of its three runs.
- Mean blinded human-rubric score is no more than 0.1 points below baseline on
  the 0-to-2 scale, with no rubric category more than 0.2 points lower.
- Median total input tokens fall by at least 15% and estimated median cost falls
  by at least 10%.
- Median wall-clock duration does not regress by more than 5%, and retries,
  tool errors, and user interventions do not increase by more than 10%.
- The full suite passes for every model family that can be used with the primary
  agent. Otherwise adoption must include an enforceable model-family lock or a
  reviewed dynamic selection mechanism; a static cross-family prompt is not
  acceptable.
- The candidate has a named maintainer, a prompt revision history, an upgrade
  review owner, and a same-day rollback path.

Adoption is a separate change from the experiment. It requires review of the
prompt text and evaluation evidence and must add the deferred guardrail in a
form that allows only the explicitly approved prompt and model scope. Do not
turn the no-prompt guardrail into a blanket exception.

## Rollback Criteria

Rollback immediately if any of these occur after adoption:

- One critical policy violation.
- Deterministic task success falls more than 2 percentage points below the
  recorded baseline over a rolling sample of at least 30 comparable sessions.
- Tool errors, retries, or user interventions rise by more than 10% over the
  recorded baseline for 30 comparable sessions.
- Token savings fall below 10%, median duration regresses by more than 10%, or
  the provider changes prompt or tool-calling requirements.
- The active model family is not covered by the approved evaluation.
- An OpenCode upgrade changes replacement semantics or any relevant upstream
  model-family prompt before reevaluation is complete.

Rollback means removing the approved prompt field or file from its source,
running `bash setup.sh`, confirming with `opencode debug config` that both
primary prompt fields are absent, and restarting OpenCode outside an active
agent run. Preserve sanitized evidence, but do not preserve the override in a
disabled production fragment.

## OpenCode Upgrade Review

Every `opencodePin` change must review primary-prompt behavior, even while the
fields remain unset.

For the old and new tags:

1. Diff `packages/opencode/src/session/llm/request.ts` to confirm whether
   `agent.prompt` still replaces `SystemPrompt.provider(model)`.
2. Diff `packages/opencode/src/session/system.ts` and the complete
   `packages/opencode/src/session/prompt/` directory for model-family routing
   and instruction changes.
3. Diff `packages/opencode/src/agent/agent.ts` for built-in agent defaults and
   configuration merge semantics.
4. Check the current [agent docs](https://opencode.ai/docs/agents/) and
   [configuration schema](https://opencode.ai/config.json) for prompt shape,
   interpolation, precedence, or deprecation changes.
5. Run `opencode debug config` after activation and record that
   `agent.build.prompt`, `agent.plan.prompt`, and deprecated `mode.*.prompt`
   remain absent.
6. Run `nix flake check` according to `docs/OpenCode Versioning.md`. Once the
   deferred no-prompt test exists, confirm that `opencode-tests` includes and
   passes it.
7. Record the reviewed source paths and conclusion in the upgrade change or
   merge request. "Schema unchanged" is insufficient because prompt routing is
   runtime behavior.

If a replacement prompt has ever been adopted, stop the upgrade until the full
behavioral suite passes on the new OpenCode version and every allowed model
family. If only the isolated experiment exists, discard its prior results when
upstream changes the relevant base prompt and establish a new baseline before
reconsideration.

## Decision Checklist

- [ ] Primary prompt fields are absent from all normal configuration layers.
- [ ] Reconsideration prerequisites and one pressure signal are measured.
- [ ] Experiment files and databases are temporary and outside normal config.
- [ ] Baseline and candidate use identical versions, models, tasks, and commits.
- [ ] All 72 behavioral-evaluation runs are scored and retained in aggregate.
- [ ] Every adoption criterion passes for every allowed model family.
- [ ] Rollback owner and commands are documented before adoption.
- [ ] Every OpenCode upgrade reviews prompt routing and upstream prompt diffs.
