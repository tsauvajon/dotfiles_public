---
name: dotfiles-config
description: Use when editing this dotfiles repo, Home Manager-managed config, OpenCode config, AGENTS.md, opencode.json, commands, skills, agents, plugins, MCP servers, or permission rules.
---

# Dotfiles Config

This repo is the source of truth for Home Manager-managed configuration. Do not edit generated or linked files under `~/.config/opencode`, `~/.config/task`, `~/.cargo`, or similar locations directly when they point into `/nix/store`.

## Source Layout

- Public sources: `config/<tool>/`, `home/`, `home/hosts/`, and repo-local `.opencode/`.
- Private overlay: `~/.config/dotfiles/`.
- Generated OpenCode target: `~/.config/opencode/`.
- Private OpenCode setup files: `~/.config/dotfiles/config/opencode/`.

## OpenCode Config

- Public OpenCode sources live in `config/opencode/`.
- Repo-local dotfiles-only OpenCode commands and skills live in `.opencode/`.
- Private OpenCode overlay files live under `~/.config/dotfiles/config/opencode/`.
- Generated files under `~/.config/opencode/` are not edit targets.
- Commands, skills, agents, plugins, rules, primary rules, and JSON fragments are merged by `home/opencode.nix`.
- If changing merge behavior, update tests under `home/opencode.test/` or `home/lib/*.test.nix` and run `nix flake check`.

## Private Overlay

- The private flake lives at `~/.config/dotfiles/flake.nix`.
- `setup.sh` builds with `--override-input private "path:$HOME/.config/dotfiles"`, so private edits are read directly from the working tree and do not require a commit or lockfile update.
- Keep private or organization-specific content in the private overlay, not in this public repo.
- Every private field except `git.{name,email,signingKey}` is optional. Prefer omitted or `null` optional values over empty-string placeholders.

## Activation

Run from this repo after source or private-overlay changes that affect generated config:

```sh
bash setup.sh
```

After activation, re-read generated files before validating them because Home Manager may atomically replace symlinks with new `/nix/store` targets. If setup is run from inside OpenCode, the shared server restart may be deferred; run `bash setup.sh` from a normal shell to restart safely.

## OpenCode Schema And Restart

- Validate unfamiliar OpenCode config shapes against `https://opencode.ai/config.json` before writing.
- `opencode.json` config is strict; invalid fields can prevent startup.
- Config, agent, command, skill, and plugin changes are loaded at OpenCode startup. Existing sessions keep using already-loaded config until OpenCode restarts.
- Prefer file-based agents, commands, skills, and plugins over large inline JSON blocks.
- Do not set `agent.build.prompt` or `agent.plan.prompt`; those replace the model-family base prompt.

## Nix Notes

- When referencing flake inputs, use the attribute name from local `flake.nix`, not the upstream repository or URL slug.
- `flake.lock` pins branch inputs to exact commits. Use `nix flake metadata` to inspect resolved revisions.
- On macOS, `/usr/bin/git` may be an Xcode command line tools stub. For Nix fetch/debug flows, prefer a Nix-provided git invocation such as `nix run nixpkgs#git -- ...` when system git behavior is suspect.
- For architecture-specific package issues, inspect `flake.nix`, `home/editors.nix`, and the target system before planning.

## Constraints

- Do not edit `/nix/store` symlink targets.
- Do not introduce tools or helpers that are not already provided by this repo.
- Keep edits ASCII unless the target file already requires Unicode.
- Keep excluding `rules/daily-briefing.md` from the second-brain OpenCode import unless automatic morning briefings are explicitly requested again.
