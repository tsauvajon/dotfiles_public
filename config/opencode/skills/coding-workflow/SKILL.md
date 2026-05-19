---
name: coding-workflow
description: Use for non-trivial design, implementation, refactoring, debugging, or testing work. Provides a pragmatic engineering workflow for planning, code changes, verification, quality gates, and recovery when stuck.
compatibility: opencode
metadata:
  status: stable
  version: "0.1.0"
---

# Coding Workflow

Apply this skill when a coding task needs deliberate design, multiple steps, meaningful tests, or debugging. Keep the workflow proportional: do not add process for simple mechanical edits.

## Philosophy

- Prefer incremental progress over big bangs.
- Learn from existing code before implementing.
- Be pragmatic over dogmatic.
- Choose clear intent over clever code.
- Keep the happy path aligned to the left.

## Simplicity

- Give each function or type one responsibility.
- Avoid premature abstractions.
- Choose boring code over clever tricks.
- Prefer self-documenting names, types, and structure over comments.
- If the code needs a long explanation, look for a simpler shape.

## Planning

For complex work, break the task into 3-5 stages. If the plan needs to persist across turns or agents, document it in `IMPLEMENTATION_PLAN.md`:

```markdown
## Stage N: [Name]
**Goal**: [Specific deliverable]
**Success Criteria**: [Testable outcomes]
**Tests**: [Specific test cases]
**Status**: [Not Started|In Progress|Complete]
```

- Update the plan as work progresses.
- Remove the plan file when all stages are done.
- Skip the file for small tasks where the todo list or final summary is enough.

## Implementation Flow

1. Understand the surrounding code and existing patterns.
2. Identify the smallest behavior change that satisfies the request.
3. Add or update tests first when practical.
4. Implement the minimal code needed to pass.
5. Refactor only after behavior is covered and verification is green.
6. If a commit is part of the requested workflow, commit only after verification passes and the change is complete.

## When Stuck

After 3 failed attempts on the same issue, stop and reassess.

1. Document what failed: attempted fix, exact error, and likely cause.
2. Find 2-3 similar implementations or adjacent patterns.
3. Question the abstraction level and whether the problem can be split smaller.
4. Try a different angle: use a simpler design, remove an abstraction, or use an existing library/framework feature.

## Technical Standards

- Prefer composition over inheritance.
- Prefer explicit data flow over hidden globals.
- Use interfaces, traits, or adapters where they improve testability.
- Fail fast with descriptive errors and useful context.
- Handle errors at the correct boundary.
- Never silently swallow exceptions or failed results.

## Decision Framework

When multiple valid approaches exist, choose by:

1. Testability: can this be verified easily?
2. Readability: will this be clear in six months?
3. Consistency: does it match project patterns?
4. Simplicity: is it the smallest design that works?
5. Reversibility: how hard is it to change later?

## Project Integration

- Find similar features, components, or tests before inventing a new pattern.
- Use the project’s existing libraries and helpers when possible.
- Use the project’s existing build, test, formatter, and linter commands.
- Prefer Nix-provided tools when the repo provides them.
- Do not introduce new tools without strong justification.

## Quality Gates

Before calling work complete, check that:

- Tests for new or changed behavior are written when practical.
- Relevant tests pass.
- Code follows project conventions.
- Formatter and linter warnings are addressed.
- No TODOs are added without an issue number or clear follow-up.
- The implementation matches the plan and user request.

## Test Guidelines

- Test behavior, not implementation.
- Prefer deterministic tests.
- Use existing test utilities and fixtures.
- Give tests names that describe the scenario.
- Organize tests by module or suite rather than relying on broad test-name prefixes.

## Reminders

- Never use `--no-verify` unless explicitly instructed.
- Never disable tests instead of fixing them.
- Never claim success without running the relevant verification or clearly stating what was not run.
- Verify assumptions against the codebase.
