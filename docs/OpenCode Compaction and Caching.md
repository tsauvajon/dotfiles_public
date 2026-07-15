# OpenCode Compaction and Caching

This is the deferred implementation runbook for Fix 11. Do not enable a knob
from this page without first completing the sanitized A/B test below.

## Decision

Defer the configuration change until a representative, non-sensitive A/B test
shows a material reduction in provider input without loss of task quality or a
cache-cost regression.

The conservative first production change, if the gate passes, is only:

```json
{
  "compaction": {
    "prune": true
  }
}
```

Do not tune `reserved`, `tail_turns`, `preserve_recent_tokens`, or `auto` in the
same change. Do not combine this change with a `tool_output` experiment.

## Current State

- The merged config has no top-level `compaction` object. On the current pin,
  OpenCode defaults to automatic compaction with old tool-output pruning
  disabled. Reverify these implementation defaults after an OpenCode update.
- The private model overlay currently pins `agent.compaction` to the full-context
  `bifrost/gpt-5.6-sol` model with the `high` variant. Verify the resolved private
  model before running the experiment; this is separate from top-level
  compaction behavior settings.
- OpenCode itself is pinned to `1.18.1` in `flake.nix`. Recheck upstream behavior
  and defaults if that pin changes before this runbook is executed.
- The generated `~/.config/opencode/opencode.json` is Home Manager output. Never
  edit it directly.

The exact candidate source file is:

```text
config/opencode/opencode.compaction.json
```

That filename matches the existing public `opencode.<scope>.json` fragment
convention. `home/opencode.nix` deep-merges it into the generated global config.

## Why Defer

Pruning is promising but not free:

- Cached input still occupies the model context window; prompt caching does not
  make the context smaller.
- Pruning changes the request prefix and can trade cache reads for cache writes
  or uncached input.
- OpenCode persists a `compacted` marker on eligible old tool results. It sends
  a placeholder for those results on later model requests; it does not merely
  alter provider billing metadata.
- The pinned full-context compaction model already reduces the immediate risk of
  the compaction request itself overflowing.
- There is not yet sanitized, representative before/after evidence for this
  setup.

In OpenCode `1.18.1`, pruning skips recent turns and protected tools, preserves
roughly 40,000 estimated tokens of older tool output, and only applies a batch
when more than roughly 20,000 estimated tokens would be removed. These are
implementation details, not stable configuration guarantees; see the pinned
[`compaction.ts` source](https://github.com/anomalyco/opencode/blob/v1.18.1/packages/opencode/src/session/compaction.ts).

## Token Accounting

OpenCode normalizes provider usage so its stored `tokens.input` excludes cache
reads and cache writes. Reconstruct provider input with:

```text
provider_input = tokens.input + tokens.cache.read + tokens.cache.write
```

Do not compare `tokens.input` alone between arms. A lower uncached-input value
can be offset by cache reads or writes. OpenCode's overflow fallback is:

```text
overflow_count = tokens.total
                 if tokens.total is available and non-zero
                 else provider_input + tokens.output
```

The normalization is in
[`session.ts`](https://github.com/anomalyco/opencode/blob/v1.18.1/packages/opencode/src/session/session.ts),
and the overflow calculation is in
[`overflow.ts`](https://github.com/anomalyco/opencode/blob/v1.18.1/packages/opencode/src/session/overflow.ts).

### Cache Versus Context

Keep these concepts separate when interpreting results:

- **Context size** is the content sent to the model and must fit the model's
  input window. Cache hits do not remove cached tokens from that window.
- **Prompt cache** is a provider-side billing and latency optimization for a
  repeated request prefix. Cache reads can be cheaper or faster, but those tokens
  are still context.
- **Pruning** reduces future request content by replacing eligible old tool
  results with a short marker. It can reduce context, but changing the prefix can
  also reduce cache reuse.
- A successful result improves `provider_input`, request latency, or compaction
  reliability without materially worsening cache cost or answer quality.

## Gate For Running The Experiment

Run the A/B only when all of the following are true:

1. OpenCode still supports `compaction.prune` and the generated schema accepts it.
2. A long, tool-heavy session can be exported and made safe for local testing.
3. The fixture contains enough old, non-protected tool output to cross the
   current pruning thresholds. A no-op test is not evidence against pruning.
4. Both arms can use the same OpenCode version, model, variant, agent, prompts,
   project state, and provider account.
5. The shared server does not need to be restarted or used for the experiment.
6. A verify pass confirms the current pin supports `export --sanitize`, `import`,
   `run --session --format json`, `debug config`, `OPENCODE_CONFIG_CONTENT`, and
   an observable pruning event in logs.

## Safe Sanitized-Export A/B

Use an expendable local fixture. Never test against the only copy of a useful
session.

### 1. Export And Audit

Create a private temporary directory and use OpenCode's sanitizer:

```sh
LAB="$(mktemp -d)"
chmod 700 "$LAB"
opencode export --sanitize ses_SOURCE >"$LAB/source.sanitized.json"
```

Review the complete export locally before continuing. Replace any remaining
names, paths, repository content, prompts, URLs, tokens, customer data, and other
identifiers with synthetic values. Preserve message order, tool-result shape,
and approximate output sizes. Retain only deliberately non-sensitive facts that
can be used to assess answer correctness. If the export cannot be made both safe
and representative, stop; do not upload or share it.

Treat `--sanitize` as best-effort preprocessing, not a privacy guarantee. Manual
review and redaction are mandatory regardless of the flag's output.

The official CLI documents `export --sanitize` and `import` in the
[`export` and `import` sections](https://opencode.ai/docs/cli/#export).

### 2. Create Independent Arms

Isolate every imported and generated experiment session from the default/shared
OpenCode database:

```sh
export OPENCODE_DB="$LAB/opencode-experiment.db"
```

Keep this absolute override set for every subsequent `opencode import`, `debug
config`, and `run` command in this experiment. Never import the sanitized fixture
into the default database.

Import the audited file twice and record the two new session IDs printed by the
commands:

```sh
opencode import "$LAB/source.sanitized.json"
opencode import "$LAB/source.sanitized.json"
A=ses_CONTROL_ID
B=ses_PRUNE_ID
```

Stop if the imports do not produce independent session IDs. Keep the source
export unchanged so both arms begin from identical history.

### 3. Verify The Runtime Overrides

Use inline config only for the experiment; do not edit dotfiles yet:

```sh
OPENCODE_CONFIG_CONTENT='{"compaction":{"prune":false}}' opencode debug config
OPENCODE_CONFIG_CONTENT='{"compaction":{"prune":true}}' opencode debug config
```

Confirm the first output resolves `prune` to `false`, the second resolves it to
`true`, and all other relevant model and compaction fields match. Managed or
project config must not override the intended value.

### 4. Prime Pruning, Then Measure

Pruning runs after a completed prompt loop. Run the same harmless primer in both
arms before the measured prompt:

```sh
PROMPT_1='Reply exactly READY. Do not call tools.'
PROMPT_2='Using only the prior session, summarize the final state and list the deliberately preserved test facts. Do not call tools.'

OPENCODE_CONFIG_CONTENT='{"compaction":{"prune":false}}' \
  opencode --print-logs --log-level INFO run --format json --session "$A" \
  "$PROMPT_1" >"$LAB/a-primer.jsonl" 2>"$LAB/a-primer.log"

OPENCODE_CONFIG_CONTENT='{"compaction":{"prune":true}}' \
  opencode --print-logs --log-level INFO run --format json --session "$B" \
  "$PROMPT_1" >"$LAB/b-primer.jsonl" 2>"$LAB/b-primer.log"

OPENCODE_CONFIG_CONTENT='{"compaction":{"prune":false}}' \
  opencode run --format json --session "$A" "$PROMPT_2" \
  >"$LAB/a-measure.jsonl"

OPENCODE_CONFIG_CONTENT='{"compaction":{"prune":true}}' \
  opencode run --format json --session "$B" "$PROMPT_2" \
  >"$LAB/b-measure.jsonl"
```

The prune arm is valid only if its primer log records that pruning actually
occurred. If it did not, choose a larger qualifying fixture rather than lowering
upstream thresholds. Do not attach either arm to the shared server. Repeat with
at least three qualifying fixtures; alternate arm order to reduce provider-load
bias.

### 5. Compare

For each measured response, record:

| Measure        | Comparison                                                             |
| -------------- | ---------------------------------------------------------------------- |
| Provider input | `input + cache.read + cache.write`                                     |
| Cache behavior | Read tokens, write tokens, and uncached input separately               |
| Output         | Output and reasoning tokens                                            |
| Cost           | Provider-reported/OpenCode cost for the measured turn                  |
| Latency        | Wall-clock time for the measured command                               |
| Quality        | Preserved facts correct, no invented state, useful final-state summary |
| Reliability    | No overflow, retry loop, compaction error, or malformed tool history   |

Use medians across qualifying fixtures, not a single favorable run. Preserve raw
JSONL only inside the protected temporary directory. Delete the imported test
sessions and `rm -rf "$LAB"` after the result has been recorded in sanitized
aggregate form.

## Promotion Procedure

Promote only if all qualifying fixtures retain required facts and the prune arm
shows a repeatable provider-input, latency, cost, or reliability benefit without
a material cache regression.

1. Add only `config/opencode/opencode.compaction.json` with the JSON shown at the
   top of this page.
2. Validate the JSON and run `nix flake check`.
3. Run `bash setup.sh` from a normal shell. Do not restart the shared server from
   inside an active OpenCode prompt.
4. Confirm `opencode debug config` reports `compaction.prune: true` and preserves
   the existing `agent.compaction` model pin.
5. Observe several real long sessions before considering any additional tuning.

The official [compaction configuration documentation](https://opencode.ai/docs/config/#compaction)
and [configuration schema](https://opencode.ai/config.json) are the public
contract; the pinned source is supporting implementation evidence.

## Rollback Criteria And Procedure

Rollback immediately if any of these occurs after promotion:

- A previously available old tool result is required and the placeholder causes
  a wrong answer, repeated work, or inability to continue.
- Context-overflow, compaction, malformed-history, or provider errors increase.
- Provider input does not improve on qualifying sessions, or cache writes,
  uncached input, cost, or latency materially worsen.
- Long-session answer quality regresses, including lost decisions, requirements,
  file state, or unresolved follow-ups.
- Pruning behavior changes unexpectedly after an OpenCode pin update.

Rollback by deleting `config/opencode/opencode.compaction.json` (or setting
`prune` to `false` in an emergency overlay), running `bash setup.sh` from a normal
shell, safely restarting the shared server, and verifying the resolved config.
Rollback affects future request construction; it does not remove already
persisted `compacted` markers from test or production sessions. Fork or restore
from a pre-change export if a specific session needs unpruned history.

## Separately Gated `tool_output` Experiment

`tool_output` is not a second compaction setting. It controls the immediate
truncation limits applied when tools return output. OpenCode `1.18.1` defaults to
2,000 lines and 50 KiB, writes the complete truncated result to its tool-output
directory, and retains those files for a limited period. See
[`truncate.ts`](https://github.com/anomalyco/opencode/blob/v1.18.1/packages/opencode/src/tool/truncate.ts).

Do not run this experiment until the `compaction.prune` decision is complete.
Then use new A/B fixtures and change one dimension only. The conservative first
candidate is a line-limit experiment that leaves the byte limit unchanged:

```json
{
  "tool_output": {
    "max_lines": 1000,
    "max_bytes": 51200
  }
}
```

If promoted, keep it in a separate candidate fragment:

```text
config/opencode/opencode.tool-output.json
```

Gate it on successful retrieval of details from truncated output, no additional
tool calls or task failures, and a measurable provider-input benefit. Roll it
back independently if agents miss relevant lines, depend on expired full-output
files, repeatedly reread outputs, or lose more quality than the context savings
justify. Never enable `compaction.prune` and new `tool_output` limits in the same
experiment or change, because their effects cannot then be attributed safely.
