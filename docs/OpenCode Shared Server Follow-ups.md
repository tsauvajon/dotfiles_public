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
| Memory watchdog | Evidence collected | Yes | Add report-only CPU/RSS/client warnings |
| Session and disk hygiene | Report-only | Not yet | Build a safe inventory before any destructive cleanup |
| Upstream evidence | Reproduced | Yes | Track matching upstream issues and retest future pins |

## 2026-07-13 Performance Evidence

A read-only investigation reproduced the shared-server trigger on OpenCode
`1.17.15` during active parallel work. Sanitized observations:

- Attached TUI count increased from four to eight while several sessions were
  active.
- `ps` reported about 3 GiB RSS for the shared server and roughly 0.6-0.8 GiB
  RSS for each attach client. Aggregate OpenCode CPU was regularly above 200%.
- One root session launched six subagents while another long-running session was
  already emitting frequent tool and model events.
- Every active TUI showed CPU activity, including clients not responsible for
  the busy root session. This matches process-global event fan-out.
- `shared-server-error.log` contained repeated `MaxListenersExceededWarning`
  stacks for event listeners.
- The shared health endpoint still returned successfully in about 130 ms. A
  healthy endpoint alone therefore does not prove that the server is operating
  efficiently.
- A local MCP endpoint responded in about 2 ms, ruling it out as the source of
  the sustained CPU load. Standalone remote MCP discovery took about 12 seconds,
  which is a separate startup cost.
- A configured local helper provider was unavailable or locked and generated
  repeated failures on OpenCode's 30-second retry cadence. That amplified prompt
  latency but did not explain the sustained per-TUI CPU by itself.

Use the `Shared Server Feels Slow` procedure in `docs/OpenCode Debug.md` for
immediate recovery. Restarting clears accumulated state but is not a durable
fix.

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

The status warning should report server and attach-client CPU as well as RSS.
Client count alone is insufficient because event volume determines the fan-out
cost. Keep any automatic restart disabled until repeated measurements establish
a safe threshold and active-session detection is reliable.

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

Matching upstream reports, verified on 2026-07-13:

- [#36441](https://github.com/anomalyco/opencode/issues/36441): process-global
  event fan-out sends every event to every TUI and scales CPU with client count.
- [#36445](https://github.com/anomalyco/opencode/issues/36445): reconnect cleanup
  can retain the prior HTTP event stream and listener.
- [#29204](https://github.com/anomalyco/opencode/issues/29204): repeated attach
  reconnects produce listener warnings and large memory growth.
- [#34574](https://github.com/anomalyco/opencode/issues/34574): matching Effect
  event-listener warning and multi-gigabyte RSS growth.

As of 2026-07-13, the `1.17.16` through `1.17.18` release notes did not document
a fix for this behavior. Retest pin updates, but do not treat an upgrade alone
as the current mitigation.

## References

- `home/opencode-server.nix`: shared-server service, restart deferral, pending
  restart breadcrumb.
- `home/programs/scripts.nix`: `opencode-shared`, `opencode-server-status`, and
  `opencode-reap` wrappers.
- `home/opencode.test/server-activation.nix`: restart-deferral regression tests.
- `scripts/opencode-ops.test.nix`: status and reap integration tests.
- `docs/OpenCode Versioning.md`: channel and DB selection notes.
- `docs/OpenCode Debug.md`: first-response diagnosis and safe recovery.
- `docs/OpenCode Cargo Cache.md`: per-session Cargo target isolation and cache
  cleanup notes.
