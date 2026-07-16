---
name: dotfilify
description: Move config into this dotfiles repo with optional private overlay fragments and Home Manager wiring.
compatibility: opencode
metadata:
  status: experimental
  version: "0.4.0"
---

# Dotfilify Config Setup

Use this skill to standardize a tool's config under Home Manager, with reusable public config in this repo and optional private fragments in `~/.config/dotfiles`.

## Merge Strategies

- Plain symlink: one public file or directory, no overlay needed.
- Text concat: TOML, INI, shell, or similar ordered fragments; model after `home/programs/aerospace.nix`, `cargo.nix`, or `alacritty.nix`.
- Deep JSON: fragment-only JSON partials; model after `home/opencode.nix`.
- Typed options: Nix module options backed by private flake values; model after Git, task, or goto modules.
- Directory merge: named files where private wins on collision; model after OpenCode commands/skills/agents/plugins.

## Workflow

1. Inspect the existing config and classify public, private, host-specific, and sensitive content.
2. Place reusable public content under `config/<tool>/`.
3. Place private overlays under `~/.config/dotfiles/` only when needed.
4. Wire the simplest matching Home Manager strategy in `home/`.
5. Add cleanup for previously managed paths in `home/bootstrap.nix` when needed.
6. Run `bash setup.sh` and verify the generated destination symlink or merged content.

## Constraints

- Keep private and organization-specific content out of the public repo.
- Do not edit `/nix/store` or generated symlink targets.
- Do not add new merge helpers unless existing helpers cannot express the config.
- Do not update `README.md` unless explicitly requested.
