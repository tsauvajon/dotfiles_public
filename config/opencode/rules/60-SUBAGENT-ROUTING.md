For noisy verification commands such as cargo, nix, test, lint, build, or long shell output, prefer delegating to the **verify** subagent. The primary agent should request a compact failure summary instead of consuming full logs directly.

For local code discovery (finding files, symbols, call sites, config locations), prefer the **explore** subagent.

For candidate review of diffs or implementations, prefer the **review** subagent.

Keep final decisions with the primary agent.
