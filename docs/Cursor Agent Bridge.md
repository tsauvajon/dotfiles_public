# Cursor Agent Bridge

The Cursor Agent bridge's production default is the Cursor CLI backend. It runs
the Cursor CLI as a child process with a small environment allowlist and exposes
an OpenAI-compatible local HTTP API for OpenCode.

## Experimental SDK backend

An in-process SDK backend exists as an experimental spike only. Opt in explicitly:

```sh
OPENCODE_CURSOR_AGENT_BACKEND=sdk
```

The SDK module is lazy-loaded only in this mode. By default the bridge imports
`@cursor/sdk`; tests can override this with `OPENCODE_CURSOR_AGENT_SDK_MODULE`.
`@cursor/sdk` is public beta, is intentionally not a public dotfiles dependency
yet, and the real SDK is not exercised by automated tests. The current tests use
fake SDK modules so they do not require dependency installation, network access,
or a Cursor API key. If you want to install the SDK locally for this spike, add
it to your private `~/.config/dotfiles/opencode/package.json` overlay rather
than the public `config/opencode/package.json`.

SDK authentication uses `CURSOR_API_KEY`, which is required when
`OPENCODE_CURSOR_AGENT_BACKEND=sdk`. Do not store API keys in Nix/Home Manager
environment configuration: Nix store paths and launchd/systemd service files can
expose those values. Inject secrets at runtime instead.

The SDK runs in-process and can read the bridge process environment. This is
different from the CLI backend, whose child process receives only the bridge's
explicit allowlist. Both backends can use `CURSOR_API_KEY`; the CLI subprocess
receives only that named secret plus the small allowlist, while the SDK can read
the full bridge environment.

## Current scope and tradeoffs

- There are no hosted Standard Agents in this bridge path.
- The implementation does not use reverse-engineered Cursor internals.
- There is no resume/session reuse yet; each request creates a fresh SDK run.
- `OPENCODE_CURSOR_AGENT_SDK_MODEL` overrides only the model sent to the SDK.
  OpenAI-facing response labels and metrics still use the normalized bridge
  model IDs advertised by `/models`.
- No real `@cursor/sdk` smoke test is included yet because it would require
  installing the beta dependency plus network/API-key access.
- Streaming requires `Agent.create()` + `agent.send()` + `run.stream()`; there is
  no `Agent.prompt()` fallback for streaming because that shape cannot produce
  progressive output with a cancellable run handle.
- Non-streaming prefers `Agent.create()` + `agent.send()` + `run.wait()` so the
  bridge can cancel or dispose the run on timeout/client disconnect. If a future
  SDK module only exposes `Agent.prompt()`, the bridge has a compatibility
  fallback, but that fallback has no run handle; timeout/client-close handling can
  stop waiting and record metrics, but cannot cancel the underlying SDK work.
- `OPENCODE_CURSOR_AGENT_TIMEOUT_MS` is shared with the CLI backend and controls
  SDK setup, wait, and stream-next timeouts.
- `/metrics` exposes request counts, failures, timeouts, and recent per-request
  duration by backend. It does not aggregate token usage; capture response bodies
  separately if cost comparison matters.
- `recent_requests` is capped by `OPENCODE_CURSOR_AGENT_METRICS_RECENT_LIMIT`
  (default `50`). Backend totals include validation failures and missing-key
  requests, so compare `completed`, `failed`, and `timed_out` explicitly.

## Exit criteria

Promote the SDK backend only if all of the following are true:

- Cursor documents the required SDK API as stable enough for production use.
- A real SDK smoke test exists outside the pure fake-module tests and can run in
  an explicit secret/network-enabled environment.
- Timeout, cancellation, and disconnect behavior are validated with the real SDK.
- The in-process environment exposure is accepted or mitigated.
- Session/resume behavior is either implemented or intentionally ruled out.

Remove the SDK spike instead if the SDK API remains unstable, cannot provide
reliable cancellation/cleanup, requires storing long-lived secrets in managed
config, or does not provide enough value over the production CLI backend.
