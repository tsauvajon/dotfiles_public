# OpenCode Shared Server Follow-ups

This page tracks deferred work after the global OpenCode shared-server ops
changes. The shared server remains the default model: one Home Manager-managed
`opencode serve` process on `127.0.0.1:4096`, with normal interactive clients
using `opencode attach` through `opencode-shared`.

The items below were intentionally not automated yet. Pick them up only when the
trigger fires and keep the implementation compatible with the existing restart
deferral in `home/opencode-server.nix`.

## Current Baseline

| Item | State | Trigger Met? | Next Step |
| --- | --- | --- | --- |
| Memory watchdog | Deferred | Not yet | Collect RSS/client-count data with `opencode-server-status` |
| Session and disk hygiene | Report-only | Not yet | Build a safe inventory before any destructive cleanup |
| Upstream evidence | Deferred | Not yet | Reproduce on the pinned/current OpenCode version first |

## Memory Watchdog

Problem: the shared server can grow large when many attach clients and sessions
fan out events. The warning to watch for is `MaxListenersExceededWarning` in
`~/.local/share/opencode/shared-server-error.log`.

Why deferred: a restart watchdog can cut active OpenCode transports if it is not
client-aware. The status tooling exists now; the threshold and restart policy do
not.

Trigger this work when one of these is true:

- `opencode-server-status` shows repeated high RSS for the server process.
- Listener warnings recur on the pinned/current OpenCode version.
- Local slowdown correlates with the shared server, not just active client TUIs.
- There are many long-lived attach clients after running `opencode-reap` dry-run.

Acceptance criteria:

- Reports server RSS, uptime, health, and attached TUI client count before any
  restart decision.
- Restarts only when safe: no active prompt/tool run should be cut.
- Respects the pending-restart breadcrumb and agent deferral behavior in
  `home/opencode-server.nix`.
- Defaults to disabled or report-only until thresholds are validated.
- Has tests for threshold, healthy server, unhealthy server, and deferred restart
  paths.

Likely first implementation: add a status-only warning threshold to
`opencode-server-status`; do not add a timer until the warning has proven useful.

## Session And Disk Hygiene

Problem: stale attach clients, session history, tool output, snapshot repos, and
logs can grow over time. This is primarily a disk and hygiene concern, not a RAM
fix.

Why deferred: session deletion is destructive, SQLite cleanup does not shrink DB
files without an explicit `VACUUM`, and the shared server is the live DB writer.

Trigger this work when one of these is true:

- `opencode-reap` repeatedly reports stale orphan attach clients.
- `~/.local/share/opencode/` becomes a material disk consumer.
- `shared-server.log` or `shared-server-error.log` grows large enough to matter.
- Old sessions need an explicit retention policy.

Acceptance criteria:

- Starts with a report-only inventory: DB sizes, session age buckets,
  `snapshot/`, `tool-output/`, `storage/session_diff/`, and log sizes.
- Keeps `opencode-reap` dry-run by default; any destructive cleanup requires an
  explicit flag.
- Never deletes sessions from SQLite directly unless foreign keys, channel, and
  server-stop requirements are proven on a copy first.
- Treats snapshot repos as project-shared data; prefer non-destructive `git gc`
  over deletion.
- Documents retention thresholds before applying them.

Likely first implementation: add a report-only `opencode-storage-report` helper
instead of extending `opencode-reap` into DB cleanup.

## Upstream Evidence

Problem: the listener warnings and server RSS growth likely need an upstream
OpenCode fix. Local mitigations help operations, but they should not hide useful
reproduction data.

Why deferred: upstream issues need evidence from the pinned/current version and a
small reproduction. Filing based only on stale logs creates noise.

Trigger this work when one of these is true:

- The listener warning reproduces after restarting the shared server on the
  current pinned OpenCode version.
- Server RSS grows past the chosen diagnostic threshold while attach client count
  and logs are captured.
- A pin bump does not resolve the warning/memory behavior.

Acceptance criteria:

- Captures OpenCode version, OS version, shared-server command, attach-client
  count, MCP count, RSS timeline, socket state, and warning stack/log lines.
- Checks whether a matching upstream issue already exists before opening a new
  one.
- Uses `OPENCODE_AUTO_HEAP_SNAPSHOT=1` only for a targeted diagnostic run, not as
  default daily configuration.
- Records the upstream issue link in this document after filing or commenting.

Likely first implementation: add a short evidence collection script or checklist
once `opencode-server-status` output has shown a reproducible threshold.

## References

- `home/opencode-server.nix`: shared-server service, restart deferral, pending
  restart breadcrumb.
- `home/programs/scripts.nix`: `opencode-shared`, `opencode-server-status`, and
  `opencode-reap` wrappers.
- `home/opencode.test/server-activation.nix`: restart-deferral regression tests.
- `scripts/opencode-ops.test.nix`: status and reap integration tests.
- `docs/OpenCode Versioning.md`: channel and DB selection notes.
- `docs/OpenCode Cargo Cache.md`: per-session Cargo target isolation and cache
  cleanup notes.
