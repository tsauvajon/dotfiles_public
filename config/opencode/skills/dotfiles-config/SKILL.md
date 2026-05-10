---
name: dotfiles-config
description: Use when editing this dotfiles repo, Home Manager-managed config, OpenCode config, AGENTS.md, opencode.json, commands, skills, agents, plugins, MCP servers, or permission rules.
---

# Dotfiles Config

This dotfiles repo is the source of truth for Home Manager-managed config. Most live files under `~/.config/`, `~/.cargo/`, and similar locations are symlinks into `/nix/store` and are read-only.

Do not edit generated or linked files directly. Edit the repo source under `config/<tool>/`, the matching `home/<module>.nix`, or the private overlay under `~/.config/dotfiles/`, then run:

```sh
bash setup.sh
```

After `setup.sh` runs, re-read any file before retrying an edit. Home Manager may have swapped a symlink to a new `/nix/store` target, so cached file contents can be stale.

## OpenCode Config

Global OpenCode config is generated from this repo plus private overlays:

- Public sources: `config/opencode/`
- Private overlays: `~/.config/dotfiles/opencode/`
- Generated target: `~/.config/opencode/`

Public `AGENTS.md` fragments in `config/opencode/rules/` apply globally after activation. Do not put repo-specific pitfalls there. For repo-local guidance, use this repo's root `AGENTS.md` or project skills under `.opencode/skills/`.

OpenCode commands, skills, agents, plugins, rules, and JSON fragments are merged by `home/opencode.nix`. If changing merge behavior, update the co-located tests under `home/opencode.test/` or `home/lib/*.test.nix` and run `nix flake check`.

## Private Config

The private flake lives at `~/.config/dotfiles/flake.nix`. `setup.sh` builds with `--override-input private "path:$HOME/.config/dotfiles"`, so private changes are read directly from the working tree and do not require a commit or lockfile update.

Every private field except `git.{name,email,signingKey}` is optional. Optional values should be omitted or set to `null`; do not use empty strings as placeholders.

## Nix Notes

When referencing flake inputs, use the attribute name from the local `flake.nix`, not the upstream repository or URL slug. Check the `inputs = { ... }` block first.

`flake.lock` pins branch inputs to exact commits. Use `nix flake metadata` to see the resolved revision before assuming a branch reference changed.

On macOS, `/usr/bin/git` may be an Xcode command line tools stub. For Nix fetch/debug flows, prefer a Nix-provided git invocation such as `nix run nixpkgs#git -- ...` when system git behavior is suspect.

For architecture-specific package issues, inspect current files before planning. In particular, verify `flake.nix`, `home/editors.nix`, and the target system (`aarch64-darwin`, `x86_64-darwin`, or `x86_64-linux`) rather than relying on stale notes.
