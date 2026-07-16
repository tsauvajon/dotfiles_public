---
name: add-private-mcp
description: Add or update an OpenCode MCP server in the private dotfiles overlay and verify connectivity.
compatibility: opencode
metadata:
  status: experimental
  version: "0.2.0"
---

# Add Private MCP Server

Use this skill when an MCP server should be configured privately in `~/.config/dotfiles/config/opencode/` so secrets and local-only endpoints stay out of the public repo.

## Workflow

1. Collect the server key, type (`remote` or `local`/stdio), URL or command array, enabled state, and any required env/header values.
2. Never write secrets to repo-tracked public files. If a required secret is missing, ask for the exact value or a 1Password/env indirection.
3. Edit a private `opencode.*.json` fragment under `~/.config/dotfiles/config/opencode/` and preserve unrelated MCP entries.
4. Run `bash setup.sh` from `~/dev/dotfiles`.
5. Verify with `opencode mcp list`; use `opencode mcp debug <name>` when auth or connectivity needs inspection.

## Constraints

- Do not edit `~/.config/opencode/opencode.json` directly.
- Do not use placeholders for secrets.
- Keep public config free of private endpoints and tokens.
