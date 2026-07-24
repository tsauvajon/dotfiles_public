# Grok And OpenCode

This note captures the current state of `cursorapi/grok-4.5` through API for
Cursor (`standardagents/composer-api`) in this dotfiles setup.

## Summary

Grok works through the local API for basic chat completions and direct
OpenAI-compatible tool-call requests, but it does not currently work as a full
OpenCode agent model.

The failing OpenCode shape is the normal agent loop with OpenCode's full tool
inventory. Grok repeatedly finishes with `finish_reason=tool_calls` but provides
no usable tool-call payload for OpenCode to execute. Treat `cursorapi/grok-4.5`
and `cursorapi/grok-4.5-fast` as experimental and do not assign them to primary,
helper, or subagent roles that need tools.

Use `cursorapi/composer-2.5` or `cursorapi/composer-2.5-fast` for API for Cursor
agent work.

## Current Package State

The Nix package still builds the pinned `standardagents/composer-api` app from
source, with the PR 27 lifecycle fix source pin preserved. The local package now
patches the app's npm lock to bundle `@cursor/sdk` `1.0.24` instead of `1.0.13`.

Relevant files:

- `pkgs/api-for-cursor/default.nix`
- `pkgs/api-for-cursor/cursor-sdk-1.0.24.patch`
- `pkgs/api-for-cursor/start-server-running-keychain-unlock.patch`
- `config/opencode/opencode.provider.cursorapi.json`

The package exposes these model ids in OpenCode:

- `cursorapi/composer-2.5`
- `cursorapi/composer-2.5-fast`
- `cursorapi/grok-4.5`
- `cursorapi/grok-4.5-fast`

## Validated Behavior

After rebuilding, activating, restarting API for Cursor, and unlocking the saved
Cursor key, the app was healthy on the expected ports:

```sh
lsof -nP -iTCP -sTCP:LISTEN | rg 'API|node.*(8787|8788|8792)|8787|8788|8792'
curl --fail --silent --max-time 5 http://127.0.0.1:8787/health \
  | jq '{status, ready, apiKeyUnlocked}'
curl --fail --silent --max-time 5 http://127.0.0.1:8792/health
```

Expected state:

- API listener on `127.0.0.1:8787`
- SDK bridge listener on `127.0.0.1:8792`
- no API listener on `127.0.0.1:8788`
- health reports `ready: true` and `apiKeyUnlocked: true`

Basic Grok text completion works:

```sh
curl --fail-with-body --silent --show-error --max-time 180 \
  http://127.0.0.1:8787/v1/chat/completions \
  -H 'Authorization: Bearer cursor-local' \
  -H 'Content-Type: application/json' \
  --data-binary '{"model":"grok-4.5","stream":false,"messages":[{"role":"user","content":"Reply with exactly PONG and nothing else."}]}' \
  | jq '{model, finish_reason:.choices[0].finish_reason, content:.choices[0].message.content, error}'
```

Observed result:

```json
{
  "model": "grok-4.5",
  "finish_reason": "stop",
  "content": "PONG",
  "error": null
}
```

Direct OpenAI-compatible tool calls also work when the request has a small,
explicit tool inventory. A request requiring `lookup_secret({"key":"alpha"})`
emitted a normal `tool_calls` delta, and a follow-up request containing the tool
result returned the expected final assistant text.

## Failing OpenCode Shape

This OpenCode smoke still fails to converge:

```sh
opencode run --model cursorapi/grok-4.5 --format json \
  'Use the read tool to read the first line of README.md, then reply with exactly: DOTFILES_READ_OK'
```

Observed behavior:

- repeated `step_finish` events with `reason="tool-calls"`
- no visible OpenCode `read` tool execution
- no final `DOTFILES_READ_OK`
- command eventually times out

This is different from the old `Cursor SDK run failed` symptom. With SDK
`1.0.24`, Grok can run, but the full OpenCode tool-agent loop still cannot get a
usable tool payload.

## Why It Fails

The local API path is:

1. OpenCode sends an OpenAI-compatible request to `http://127.0.0.1:8787/v1`.
2. The Swift API for Cursor app converts the request for the local Cursor SDK
   bridge.
3. `cursor-sdk-local-agent-bridge.mjs` runs `@cursor/sdk` local agents and
   translates Cursor SDK events back to OpenAI-compatible responses.
4. OpenCode expects complete OpenAI `tool_calls` so it can execute local tools.

With Grok and the full OpenCode tool inventory, Cursor SDK reports a tool-call
finish, but API for Cursor does not receive or emit a complete tool-call payload
that OpenCode can execute. The issue is below OpenCode provider metadata and
above simple text generation.

Evidence against simpler causes:

- The local API is reachable on `8787`.
- The saved Cursor key is unlocked.
- `/v1/models` advertises Grok.
- Grok text completions work.
- Direct small-tool OpenAI-compatible Grok requests work.
- The failure only appears with the full OpenCode agent tool inventory.

## Patches Retained

The SDK bump is retained because it changes Grok from the older opaque
`Cursor SDK run failed` behavior to working basic and direct-tool API behavior.

The Keychain unlock patch is retained because it fixes a separate API for Cursor
bug: the app could start on `8787`, then an unlock/start action called
`startServer()` again while already running, cancelled the first listener, and
fell back to `8788` after losing to its own socket. The patch makes the
already-running unlock path update key state without rebinding the listener.

The package install check now verifies:

- bundled `@cursor/sdk` is the pinned version
- `CursorAPITransportDefaults.plist` contains the matching SDK client version
- the SDK's native `rg` helper exists and is signed
- the existing request-size bridge patch is present

## Patches Tried And Removed

Two bridge experiments were tried and then removed because they did not make the
OpenCode smoke pass:

- Capturing completed client-MCP stream events.
- Replacing stdio client MCP forwarding with SDK `local.customTools`.

Both were plausible based on SDK `1.0.24` APIs and stream shapes, but the
end-to-end OpenCode run still looped with empty tool-call finishes. Keeping those
patches would add risk to Composer without solving Grok.

## Port Recovery

The API must stay on `127.0.0.1:8787`; OpenCode is configured for that URL. If it
falls back to `8788`, use the runbook in [API for Cursor](API%20for%20Cursor.md).

Important details:

- stop the app and all `cursor-sdk-local-agent-bridge.mjs` processes
- wait for `8787`, `8788`, and `8792` listeners to disappear
- wait again before rewriting preferences
- reset both `CursorAPI.settings.v1` and `CursorAPI.sdkBridgePort.v1`
- delete the stale bridge-port key before writing `8792`
- use the current `cursorSdkVersion` from `pkgs/api-for-cursor/default.nix` in
  the settings JSON

## Recommendation

Do not spend more time patching OpenCode provider metadata for Grok. The metadata
is not the blocker.

Future useful paths:

- Update API for Cursor or `@cursor/sdk` again when upstream changes local Grok
  agent/tool behavior.
- Re-test the same three probes after any SDK bump: text completion, direct small
  tool call, and full OpenCode `read` smoke.
- Prefer Composer for day-to-day API for Cursor agent work until Grok emits
  usable tool-call payloads with OpenCode's full inventory.
