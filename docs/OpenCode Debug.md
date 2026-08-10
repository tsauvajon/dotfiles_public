# OpenCode Debug

This is the public-safe first-response checklist for local OpenCode failures in
the dotfiles setup. Keep examples sanitized: use placeholders for session ids,
workspace directories, and repositories; do not paste private repo names,
local-only tooling, credentials, or machine-specific paths. The only real
workspace path that belongs in this note is `~/dev/dotfiles`.

## Quick Orientation

Start by identifying which OpenCode surface is involved:

- TUI/attach client: the visible terminal UI.
- Shared server: the long-lived `opencode serve` process reused by attach clients.
- Generated config: the active config produced from `~/dev/dotfiles` plus local-only inputs.
- Session database: the SQLite file selected by the OpenCode binary channel.
- Tool process: a shell command, subagent, MCP call, or editor bridge launched by OpenCode.

Useful first commands:

```sh
opencode --version
opencode debug info
opencode debug paths
opencode-server-status
```

Use `opencode debug paths` instead of hard-coding OpenCode data, config, or log
directories. When sharing output, redact home paths, repo names, session ids,
and any private provider/tool names.

## Dynamic Paths

Resolve OpenCode-managed directories from the binary that is actually on `PATH`:

```sh
DATA_DIR=$(opencode debug paths | awk '$1 == "data" { print $2 }')
LOG_DIR=$(opencode debug paths | awk '$1 == "log" { print $2 }')
CONFIG_DIR=$(opencode debug paths | awk '$1 == "config" { print $2 }')

: "${DATA_DIR:?could not resolve OpenCode data dir}"
: "${LOG_DIR:?could not resolve OpenCode log dir}"
: "${CONFIG_DIR:?could not resolve OpenCode config dir}"
```

For dotfiles source changes, edit `~/dev/dotfiles`, then activate from a normal
shell when possible:

```sh
cd ~/dev/dotfiles
bash setup.sh
```

Do not edit generated OpenCode files directly. Rebuild from dotfiles sources and
then inspect the generated output only as evidence.

## Symptom: No Visible Progress

This can be a stale permission/tool state rather than live work. A common shape
is:

- A tool call is persisted as `running`.
- The real process is gone, or no matching process exists.
- Later prompts such as `continue` are saved as user messages.
- No later assistant `process` or `stream` event is emitted.
- The log shows a permission `asking id=...` around the stale tool start time,
  with no later completion or approval.

Check which DB owns the session and whether there are stale running tools:

```sh
DATA_DIR=$(opencode debug paths | awk '$1 == "data" { print $2 }')
: "${DATA_DIR:?could not resolve OpenCode data dir}"

for db in "$DATA_DIR"/opencode*.db; do
  printf '== %s ==\n' "${db##*/}"
  sqlite3 "file:$db?mode=ro" \
    "SELECT id, directory, title, datetime(time_updated / 1000, 'unixepoch') FROM session WHERE id LIKE 'ses_<prefix>%';"
done

sqlite3 "file:$DATA_DIR/<owning-db>?mode=ro" \
  "SELECT id, message_id, json_extract(data, '$.tool'), json_extract(data, '$.state.input.command')
   FROM part
   WHERE session_id = 'ses_<id>'
     AND json_extract(data, '$.type') = 'tool'
     AND json_extract(data, '$.state.status') = 'running'
   ORDER BY time_created;"
```

Check logs around the tool start time:

```sh
LOG_DIR=$(opencode debug paths | awk '$1 == "log" { print $2 }')
: "${LOG_DIR:?could not resolve OpenCode log dir}"

rg 'ses_<id>|asking id=|stream error|process .* error' "$LOG_DIR"
```

Compare with current processes, but treat process output as sensitive because it
often includes workspace paths and command arguments:

```sh
pgrep -af 'opencode|cargo|rustc|node|bun'
```

Safe recovery options:

```sh
OPENCODE_SHARED_HOST=${OPENCODE_SHARED_HOST:-127.0.0.1}
OPENCODE_SHARED_PORT=${OPENCODE_SHARED_PORT:-4096}

opencode attach "http://${OPENCODE_SHARED_HOST}:${OPENCODE_SHARED_PORT}" --dir <workspace-dir> -s ses_<id> --mini --no-replay
opencode attach "http://${OPENCODE_SHARED_HOST}:${OPENCODE_SHARED_PORT}" --dir <workspace-dir> -s ses_<id> --fork --mini --no-replay
```

Use the first command to answer or cancel the stale prompt if the UI renders. Use
`--fork` when the original session remains wedged. Avoid editing the SQLite DB
directly; if DB surgery ever looks necessary, stop the shared server and test on
a copy first.

Use the `directory` column from the session query for `<workspace-dir>`; for
dotfiles sessions that value is `~/dev/dotfiles`.

## Symptom: Session Not Found

OpenCode session lookup is database-channel specific. The binary channel chooses
which SQLite DB is used, so a session may exist on disk while the current binary
looks in a different DB.

Find the owning DB:

```sh
DATA_DIR=$(opencode debug paths | awk '$1 == "data" { print $2 }')
: "${DATA_DIR:?could not resolve OpenCode data dir}"

for db in "$DATA_DIR"/opencode*.db; do
  printf '== %s ==\n' "${db##*/}"
  sqlite3 "file:$db?mode=ro" \
    "SELECT id, directory, project_id, title FROM session WHERE id LIKE 'ses_<prefix>%';"
done
```

If the session is in a different channel DB, recover by using the binary/channel
that owns it, or export/import the session into the active channel. Prefer
keeping one stable OpenCode channel on `PATH` before forcing a global DB name;
sharing one DB across binary channels can make rollback risky after migrations.

## Symptom: Config Or Env Changes Do Not Apply

The shared server owns the runtime environment for attached sessions. Updating a
shell config or generated OpenCode file is not enough if the server process is
still running with old environment and config.

Checklist:

- Edit source under `~/dev/dotfiles`, not generated files.
- Run `bash setup.sh` from a normal shell.
- Check `opencode-server-status` after activation.
- Restart the shared server only when no active prompt or tool run will be cut.
- If activation happens inside an OpenCode agent, defer the shared-server restart
  and rerun setup from a normal shell later.

Relevant source areas in `~/dev/dotfiles`:

- `home/opencode.nix`: OpenCode config merge wiring.
- `home/opencode-server.nix`: shared-server service and restart deferral.
- `home/programs/scripts.nix`: `opencode-shared`, `opencode-server-status`, and `opencode-reap`.
- `config/opencode/`: public OpenCode fragments, commands, skills, agents, plugins, and rules.

## Symptom: Shared Server Feels Slow

The shared server is useful because it keeps MCP/config warm and shares sessions
and permissions, but many long-lived attach clients can still make the machine
feel slow. The server also fans out events to attached clients, so listener
warnings or high RSS should be investigated before adding automated restarts.
One busy session can amplify the problem by launching several subagents: every
process-global event is then delivered to every attached TUI, including idle
clients.

Checklist:

- Run `opencode-server-status`.
- Check CPU and RSS for both the shared server and every attach client:

  ```sh
  ps -axo pid,rss,%cpu,etime,command | rg 'opencode (serve|attach)'
  ```

- Check whether many attach clients are still alive or whether one root session
  is running a high-volume parallel workload.
- Run `opencode-reap` in dry-run mode before using `opencode-reap --apply`.
- Check `shared-server-error.log` for `MaxListenersExceededWarning`, and the main
  OpenCode log for repeated `stream error` entries.
- Separate shared-server saturation from a failing helper provider. If a local
  provider backs `small_model`, a configured title agent, or `bash-runner`, confirm
  that its port is listening and its model endpoint succeeds. Repeated failures
  at roughly 30-second intervals indicate OpenCode retry backoff rather than
  useful work.
- Measure each MCP endpoint before blaming MCP initialization. A healthy local
  endpoint can respond in milliseconds while an unrelated remote discovery or
  provider call is stalled.
- Prefer closing stale clients over restarting during active work.
- Cancel unneeded parallel agents before recovery; otherwise a fresh server can
  immediately return to the same event load.
- Restart the shared server only from a normal shell and only after active
  prompts and tools are safe to interrupt. A restart clears retained listeners
  and memory but does not fix the underlying fan-out behavior.
- Collect version, server status, client count, and redacted logs before filing
  or debugging an upstream issue.

See `docs/OpenCode Shared Server Follow-ups.md` for the longer-term watchdog and
hygiene plan.

## Symptom: Wrapper Command Behaves Like A Directory

The shared wrapper treats normal non-option arguments as project directories for
TUI launches. If a real OpenCode service/control subcommand is missing from the
wrapper passthrough list, it can be interpreted as a directory and produce raw
TUI output in a non-TTY context.

Checklist:

- Verify the wrapper passthrough list in `home/programs/scripts.nix`.
- Use the generated wrapper only for commands it explicitly passes through.
- For service recovery, prefer the OS service manager or the dedicated status
  script over guessing unsupported wrapper subcommands.

## Symptom: Permissions Behave Backwards

OpenCode permission rules are order-sensitive and use wildcard matching, not
filesystem glob semantics.

Checklist:

- Last matching permission rule wins.
- Bash permissions match command strings, not file paths.
- `*` crosses `/`; `**` is not special for permission patterns.
- Generated JSON ordering can differ from source fragment ordering.
- Subagents with their own bash permission block do not automatically inherit all
  top-level bash allowances.
- Check the generated config when behavior differs from source fragments.

See `docs/OpenCode permissions.md` for pattern details.

## Symptom: MCP Servers Or Tools Are Missing

First separate server connection health from tool filtering. A server can be
connected while selected tools are hidden, and a tool can be visible while the
model provider rejects its generated name.

Checklist:

- Run `opencode mcp list --print-logs --log-level INFO` first.
- Rerun with `--log-level DEBUG` only when INFO is not enough; debug logs can
  expose local paths, provider names, and auth flow details.
- Inspect the generated OpenCode config, not only source fragments.
- Restart the shared server after MCP config changes when attached sessions still
  see the old server list.
- If only one agent lacks an MCP tool, check agent-specific permissions before
  changing global MCP config.
- If only one OAuth server fails, use `opencode mcp debug <name>` after ruling
  out shared auth-cache corruption.

OpenCode composes MCP tool permission keys from the configured server key and the
tool name:

```text
sanitize(serverKey) + "_" + sanitize(toolName)
```

The sanitizer replaces characters other than letters, numbers, `_`, and `-` with
`_`. Dots, slashes, colons, and spaces therefore become underscores; hyphens and
underscores are preserved.

Filtering rules:

- Tool filtering uses last-match-wins permission semantics.
- Put broad deny patterns before narrower allow patterns.
- A `true` tool rule exposes the tool and auto-allows execution.
- Long generated tool names are not truncated by OpenCode; provider-side tool
  name limits can still reject them.
- Do not assume prompts/resources use the same key shape as tools.

## Symptom: All OAuth MCPs Fail At Once

If every OAuth-backed MCP fails with the same JSON parse error, suspect the
OpenCode MCP auth cache before debugging each server separately. A truncated auth
entry can make all remote MCP transports fail while reading shared auth state.

Validate the auth cache without printing token values:

```sh
DATA_DIR=$(opencode debug paths | awk '$1 == "data" { print $2 }')
: "${DATA_DIR:?could not resolve OpenCode data dir}"

jq 'with_entries(.value |= (keys))' "$DATA_DIR/mcp-auth.json"
```

If that reports a JSON parse error:

- Back up the auth cache before changing it.
- Prefer moving the corrupt cache aside and rerunning `opencode mcp auth <name>`
  for each OAuth-backed MCP.
- If hand-recovering entries, never print or paste token values into logs, notes,
  prompts, or commits.
- Verify with `opencode mcp list --print-logs --log-level INFO`.

Use `opencode mcp logout <name>` when you need to clear one server's saved OAuth
state without touching every other entry.

## Symptom: MCP Error Looks Like OAuth But The Server Has No OAuth

Some Streamable HTTP MCP clients keep a sticky session id after `initialize`.
If the MCP server process restarts, its in-memory session table may disappear
while the OpenCode client keeps sending the old session id. Some server/client
combinations then surface a misleading OAuth-flavoured error such as an invalid
OAuth JSON response or unexpected EOF.

Checklist:

- If a local MCP daemon was restarted, restart the OpenCode client too.
- Restarting the MCP daemon again usually does not fix a wedged client session.
- Reconnect from a fresh OpenCode session before changing auth config.
- If the server has a non-MCP CLI or REST path, use that for emergency work while
  the MCP client session is wedged.
- Treat OAuth-looking errors on unauthenticated local MCPs as possible stale
  session-state errors, not immediate proof that OAuth config is wrong.

## Symptom: MCP TLS Errors Persist Through Workarounds

Certificate errors can happen in two different places with similar text:

- Local OpenCode client to remote MCP server.
- Remote MCP server to its own backend dependency.

Checklist:

- Test the remote MCP endpoint with plain HTTP/TLS diagnostic tools first.
- If direct HTTP MCP setup fails but the endpoint is reachable, use a minimal
  local `stdio` bridge to isolate the OpenCode client from the remote HTTPS path.
- If `initialize` and `tools/list` work through the bridge but `tools/call` still
  fails, the remaining error is likely inside the MCP server or its backend path.
- Check service logs at the exact tool invocation time before changing local
  OpenCode config again.
- Keep any bridge config generic and temporary unless it becomes a supported
  part of the dotfiles setup.

## Symptom: MCP Tool Call Fails With Invalid Empty Optional Fields

Some MCP-backed APIs distinguish an omitted optional field from an empty string.
If a top-level operation fails with an invalid timestamp, thread id, cursor, or
similar optional field error, inspect the tool-call JSON before changing auth or
permissions.

Checklist:

- Omit optional keys entirely when they are not set.
- Do not send `""`, `null`, or placeholder values unless the tool schema says
  that exact value is valid.
- Retry once with the optional key removed.
- Do not switch from a safer draft/read-only flow to a side-effecting send/write
  flow just to work around a validation error.

## Symptom: Cargo Is Slow, Locked, Or Weird In OpenCode

Concurrent OpenCode sessions should not share one workspace `target/` directory.
The dotfiles setup isolates Cargo targets per root OpenCode session while sharing
compiler artifacts through the managed cache wrapper.

Checklist:

- Confirm the shell environment plugin is active for Cargo workspaces.
- Check whether the command is running under the shared server environment.
- Use per-session target directories for OpenCode-managed builds.
- Do not fix native compiler problems by setting `CC` or `CXX` to multi-word
  cache wrapper commands.
- For cache-related diagnosis, prefer explicit opt-out variables over changing
  compiler variables.
- Remove stale per-session target directories only when they are no longer needed.

See `docs/OpenCode Cargo Cache.md` for the current implementation and cleanup
commands.

## Symptom: Compaction Or Long Session Recovery Fails

Long sessions can fail differently from normal prompts because compaction may use
the configured hidden compaction agent/model or the model from the triggering
message.

Checklist:

- Check the active model and generated OpenCode config.
- Try a full-context model for `/compact` recovery.
- Restart the shared server after model/config changes, but only from a safe
  normal shell.
- If the session is already wedged, fork it and compact the fork.

## Evidence To Capture

For a useful bug report or future note, capture this data and redact it before
sharing:

- OpenCode version and `opencode debug info`.
- `opencode debug paths`, with concrete paths redacted.
- `opencode-server-status`.
- Whether the session is attached to the shared server or a standalone process.
- Server and attach-client CPU/RSS sampled more than once.
- Attached-client count and the approximate number of active subagents.
- Timestamp and frequency of listener warnings and provider retries.
- Shared-server and MCP health latency, plus local provider model-endpoint
  latency.
- Owning DB filename, not full data path.
- Session title only if it is non-sensitive; otherwise replace it with `<title>`.
- Recent redacted log lines around `stream`, `process`, `asking id=`, and tool
  start/completion events.
- Current process list filtered to OpenCode and the relevant tool family, with
  workspace paths and repo names replaced by placeholders.

## References

- `docs/OpenCode Versioning.md`: binary/plugin alignment and channel DB behavior.
- `docs/OpenCode Shared Server Follow-ups.md`: shared-server health, listener warnings, and hygiene.
- `docs/OpenCode permissions.md`: permission matching rules.
- `docs/OpenCode Cargo Cache.md`: per-session Cargo target isolation.
- `docs/TOOLS.md`: managed helper commands such as `opencode-shared`, `opencode-server-status`, and `opencode-reap`.
