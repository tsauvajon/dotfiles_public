# Subagent Strategy: Context And Cost Routing

This document is a target implementation plan for the OpenCode setup in this
dotfiles repo. It describes the desired future state, not the current runtime
configuration.

## Goal

Use `openai/gpt-5.5` with high reasoning as the primary orchestrator and editor,
then delegate high-volume context gathering to cheaper subagents.

The strategy optimizes for two outcomes:

- Keep noisy evidence out of the primary session context.
- Spend cheap/free model quota on search, logs, docs, and candidate review while
  preserving final decisions for the primary model.

The most important delegation target is noisy shell output: `cargo *`, `nix *`,
test, lint, build, and other commands that can emit hundreds or thousands of
lines. These should usually run inside a cheap `verify` subagent, which returns a
small actionable summary instead of pasting logs into the main conversation.

## Core Principle

`gpt-5.5-high` is the orchestrator, editor, and final judge. Cheap subagents are
context firewalls. They gather evidence, run bounded checks, and return compact
structured reports.

Cheap agents may provide bounded candidate interpretations, but the primary
agent makes final decisions about architecture, risk, edits, and what to do next.

## Target Agent Set

| Agent | Model | Boundary | Why |
|---|---|---|---|
| `build` / primary | `openai/gpt-5.5` with high reasoning | Main conversation, synthesis, decisions, edits, final judgment. | Most capable model; spend it where judgment matters. |
| `explore` | `opencode/deepseek-v4-flash-free` | Read-only local code search. Returns file paths, line ranges, and concise evidence. | High-volume local search does not need expensive reasoning. |
| `verify` | `opencode/deepseek-v4-flash-free` | Runs bounded verification commands and summarizes only actionable output. No edits. | Highest ROI context firewall for noisy command output. |
| `review` | `opencode/qwen3.6-plus-free` | Read-only candidate review findings with severity, evidence, and suggested fixes. | Slightly stronger cheap reasoning for critique, while final judgment stays with primary. |
| `scout` | built-in cheap/external-research agent if available | External docs, dependency source, upstream implementation checks. | Avoids creating an overlapping custom `research` agent initially. |
| `general` | inherits primary model | Rare parallel implementation or complex execution where writes are needed. | Isolates context, but does not save model cost. |

## Routing Rules

| Need | Delegate To | Expected Output |
|---|---|---|
| Find local files, symbols, call sites, config locations | `explore` | Paths, line ranges, short factual summaries |
| Run `cargo`, `nix`, tests, lint, build, or noisy shell commands | `verify` | Command, exit code, relevant failures, likely files, omitted noise, next command |
| Check external docs, upstream source, dependency behavior | `scout` | Sources, verified facts, unknowns, relevance to local task |
| Review a diff or implementation for bugs/regressions | `review` | Candidate findings with severity, file:line, evidence, suggested fix |
| Implement independent work in parallel | `general` | Completed work or structured report, used sparingly |

## Output Budgets

Subagents should return structured reports rather than free-form prose.

| Agent | Default Budget |
|---|---|
| `explore` | Max 20 file references unless explicitly asked for more. |
| `verify` | Max 100-150 summarized lines. Never paste full logs by default. |
| `review` | Max 10 findings, ordered by severity. |
| `scout` | Max 5 sources and 1500 words. |
| `general` | As small as possible; summarize completed work and verification. |

## `verify` Report Format

The `verify` agent exists to absorb noisy command output. Its default response
format should be:

```markdown
Command: <exact command>
Exit code: <code>

Relevant failures:
- <file:line or command phase>: <error summary>

Likely affected files:
- <path>

Warnings worth fixing:
- <warning summary, if relevant>

Noise omitted:
- <dependency compilation, repeated warnings, long backtraces, etc.>

Suggested next command:
- <command or "none">

Unknowns:
- <anything that could not be determined>
```

`verify` must not edit files. It should not paste full logs unless the primary
agent explicitly asks for raw output.

## What To Avoid

- Do not run noisy verification commands in the primary session when the output
  is expected to be large.
- Do not ask cheap agents broad questions like "explore this repo and tell me
  what you think".
- Do not let cheap agents make final architecture or risk decisions.
- Do not create both `scout` and `research` unless `scout` is unavailable or
  insufficient in practice.
- Do not overuse `general`; it inherits the primary model and therefore does not
  save model cost.

## Implementation Plan

### Stage 1: Confirm Config Mechanics

**Goal**: Avoid invalid OpenCode config and pin the exact GPT-5.5 high shape.

**Actions**:

- Confirm the installed OpenCode schema accepts the planned agent fields.
- Confirm whether `variant: "high"` is sufficient for `openai/gpt-5.5` high
  reasoning.
- Confirm whether explicit provider options are needed instead:
  `reasoningEffort: "high"`, `textVerbosity: "low"`, or similar.
- Confirm whether built-in `scout` is available in the installed runtime or
  requires `OPENCODE_EXPERIMENTAL_SCOUT`.

**Success Criteria**:

- The config shape is known before writing agent fragments.
- The setup can fall back to custom `research` only if `scout` is unavailable or
  not useful.

### Stage 2: Configure Primary GPT-5.5 High

**Goal**: Make the primary agent use GPT-5.5 high reasoning.

**Files**:

- `config/opencode/opencode.meta.json`
- `config/opencode/opencode.agent.json`

**Planned Shape**:

```json
{
  "model": "openai/gpt-5.5",
  "agent": {
    "build": {
      "model": "openai/gpt-5.5",
      "variant": "high"
    }
  }
}
```

If runtime behavior shows `variant` is not enough, prefer explicit options:

```json
{
  "agent": {
    "build": {
      "model": "openai/gpt-5.5",
      "options": {
        "reasoningEffort": "high",
        "textVerbosity": "low"
      }
    }
  }
}
```

**Success Criteria**:

- The generated `~/.config/opencode/opencode.json` selects `openai/gpt-5.5` for
  the primary model.
- OpenCode starts without `ConfigInvalidError`.
- Runtime model display or `opencode models` confirms the model is available.

### Stage 3: Add The `verify` Subagent

**Goal**: Create a cheap, edit-denied agent for noisy command execution.

**File**:

- `config/opencode/agents/verify.md`

**Model**:

- `opencode/deepseek-v4-flash-free`

**Permissions**:

- Deny edits.
- Allow read/search/list.
- Allow bounded verification commands.
- Deny destructive git and shell operations.

**Prompt Requirements**:

- Return the `verify` report format above.
- Summarize actionable failures instead of full logs.
- Include exact command and exit code.
- Include likely affected files.
- Suggest one next command if useful.
- Never edit files.

**Success Criteria**:

- The primary agent can delegate `cargo test`, `nix flake check`, `npm test`,
  and similar commands to `verify`.
- The primary session receives compact summaries instead of raw logs.

### Stage 4: Override `explore`

**Goal**: Ensure local code search uses a cheap read-only model.

**Preferred File**:

- `config/opencode/opencode.agent.json`

**Reason**:

- `explore` is a built-in agent. A JSON override is less likely to accidentally
  replace the useful built-in prompt than a full markdown file.

**Planned Shape**:

```json
{
  "agent": {
    "explore": {
      "mode": "subagent",
      "model": "opencode/deepseek-v4-flash-free",
      "description": "Read-only local code search and fact gathering. Return paths, line ranges, and concise evidence.",
      "permission": {
        "edit": "deny",
        "read": "allow",
        "glob": "allow",
        "grep": "allow",
        "list": "allow",
        "bash": "deny"
      }
    }
  }
}
```

**Success Criteria**:

- Local search is delegated to a cheap model.
- Results are factual and include file paths and line ranges.

### Stage 5: Add Or Override `review`

**Goal**: Use a cheap stronger-reasoning model for bounded candidate review.

**Preferred File**:

- `config/opencode/opencode.agent.json` for basic config.
- `config/opencode/agents/review.md` only if a longer prompt is needed.

**Model**:

- `opencode/qwen3.6-plus-free`

**Output Format**:

```markdown
Findings:
- Severity: <critical|high|medium|low>
  File: <path:line>
  Issue: <what is wrong>
  Evidence: <why this is plausible>
  Suggested fix: <minimal fix>
  Confidence: <high|medium|low>

Open questions:
- <question, if any>
```

**Success Criteria**:

- `review` returns candidate findings ordered by severity.
- The primary model validates findings before acting on them.

### Stage 6: Use Built-In `scout` First

**Goal**: Avoid overlapping `scout` and `research` responsibilities.

**Decision**:

- Use built-in `scout` for external docs and dependency source research.
- Do not add custom `research` initially.

**Fallback**:

- Add `config/opencode/agents/research.md` only if `scout` is unavailable in the
  installed runtime or its output is not structured enough.

**Success Criteria**:

- External research has a cheap context-isolated path.
- There is no duplicate custom research agent unless real usage proves it is
  needed.

### Stage 7: Configure Task Routing

**Goal**: Make the primary agent see and use the intended subagents.

**File**:

- `config/opencode/opencode.agent.json`

**Initial Policy**:

```json
{
  "agent": {
    "build": {
      "permission": {
        "task": {
          "*": "deny",
          "explore": "allow",
          "verify": "allow",
          "review": "allow",
          "scout": "allow",
          "general": "allow"
        }
      }
    }
  }
}
```

**Iteration Rule**:

- If the primary model overuses expensive `general`, change `general` to `ask` or
  `deny`.

**Success Criteria**:

- The primary model naturally delegates noisy work to cheap agents.
- `general` remains available for rare implementation parallelism.

### Stage 8: Add A Short Global Rule

**Goal**: Teach every session to delegate noisy commands by default.

**File**:

- `config/opencode/rules/<name>.md`

**Content**:

```markdown
For noisy verification commands such as cargo, nix, test, lint, build, or long
shell output, prefer delegating to the verify subagent. The primary agent should
request a compact failure summary instead of consuming full logs directly.
```

**Success Criteria**:

- The rule improves delegation behavior without materially bloating every
  session.

### Stage 9: Validate And Smoke Test

**Goal**: Confirm the config works and the behavior saves context.

**Commands**:

```sh
nix flake check
bash setup.sh
```

Restart OpenCode after activation because config is loaded at startup.

**Generated Files To Inspect**:

- `~/.config/opencode/opencode.json`
- `~/.config/opencode/agents/verify.md`

**Behavior Tests**:

- Ask the primary agent to run a noisy verification command and confirm it uses
  `verify`.
- Ask the primary agent to find local references and confirm it uses `explore`.
- Ask for external docs or dependency source and confirm it uses `scout`.
- Ask for a diff review and confirm it uses `review`.

**Success Criteria**:

- No full build/test logs enter the primary context by default.
- `verify` returns compact, actionable reports.
- `explore` returns paths and line ranges.
- `review` returns bounded candidate findings.
- `scout` works, or a concrete decision is made to add `research`.

## Open Decisions

| Decision | Current Choice | Revisit When |
|---|---|---|
| Command-running agent name | `verify` | Only if usage suggests a clearer name. |
| External docs agent | Built-in `scout` | If `scout` is unavailable or not structured enough. |
| GPT-5.5 high config | Prefer `variant: "high"` | If runtime behavior requires explicit options. |
| `general` access | Allowed initially | If the primary overuses it and increases cost. |
| Global noisy-command rule | Add short rule | If it proves too intrusive across repos. |

## Measurement

After a week of real usage, evaluate:

- Did `verify` prevent large command outputs from entering the primary context?
- Did `explore` save time and tokens versus inline searching?
- Did `review` produce useful candidate findings or too much noise?
- Did `scout` cover external research well enough?
- Did `general` get overused despite being expensive?

Keep agents that reliably reduce primary context and cost. Tighten or remove
agents that require more primary-model cleanup than doing the work inline.
