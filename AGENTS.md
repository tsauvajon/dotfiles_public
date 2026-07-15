# Dotfiles Repo — Agent Guide

Keep this file repo-specific and short. Start with [`README.md`](README.md) for
setup, layout, private-overlay examples, and platform workflows; use
[`docs/`](docs/) for focused operational detail.

## Source of truth

- Edit shared sources in `config/<tool>/`, Home Manager wiring in `home/`, and
  host-specific wiring in `home/hosts/`.
- Do not edit live files under `~/.config/`, `~/.cargo/`, or similar paths when
  they point into `/nix/store`; Home Manager generated or linked them.
- OpenCode sources live in `config/opencode/`; generated output lives under
  `~/.config/opencode/`.
- After source or private-overlay changes, run `bash setup.sh` and re-read live
  files because activation may atomically replace their symlinks.

## Setup and private overlay

- `setup.sh` selects the host (override with `DOTFILES_HOST`), builds its Home
  Manager activation package, activates it, and performs platform setup.
- The required private flake is `~/.config/dotfiles/flake.nix`; first setup
  bootstraps it from `private.example.nix`.
- Private configuration stays outside this repo under `~/.config/dotfiles/`.
  Setup reads that working tree directly with `--override-input private`, so
  private edits require neither a commit nor `flake.lock` churn.
- Preserve compatibility with a minimal private flake containing only
  `git.{name,email,signingKey}`. All other private fields must remain optional;
  prefer omitted or `null` values over empty-string placeholders.

## Merge and generated-config changes

- OpenCode commands, skills, agents, plugins, rules, JSON fragments, and package
  metadata are merged by `home/opencode.nix` and `home/lib/opencode-merge.nix`.
- Keep merge tests co-located under `home/opencode.test/` and
  `home/lib/*.test.nix`. When merge behavior changes, update tests and run
  `nix flake check`; use `nix flake check --all-systems` for cross-platform
  evaluation or shared Nix-library behavior.

## Overlay-append merges

Cargo, AeroSpace, Alacritty, and task combine repo bases with sorted repo and
private fragments. See the relevant `home/` module and the `task` skill for the
current source and generated paths; later same-name fragments override earlier
ones before the surviving fragments are appended.

## References and skills

- Read [`docs/Dependency Updates.md`](docs/Dependency%20Updates.md) before
  dependency bumps; `nix flake update` does not cover every managed dependency.
- Load `dotfiles-config` for normal config/OpenCode edits and
  `dotfiles-nix-debug` for flake, activation, platform, or symlink failures.
- Load `dotfiles-setup` for setup/private-overlay workflows and `task` for the
  managed repository/worktree configuration.
- Do not introduce tools that are not already provided by this repo.
