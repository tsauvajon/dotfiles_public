---
name: dotfiles-nix-debug
description: Use when debugging this dotfiles repo's Nix flakes, setup.sh, Home Manager activation, private flake, x86_64-darwin, OpenCode packaging, or /nix/store symlink issues.
---

# Dotfiles Nix Debug

Use this skill for this repository only. It captures recurring failure modes from prior setup and debugging sessions.

## First Checks

Identify the target platform before diagnosing package or activation failures:

```sh
uname -s
uname -m
```

`setup.sh` maps platforms to Home Manager hosts:

- `Darwin arm64` -> `thomas-darwin`
- `Darwin x86_64` -> `thomas-darwin-intel`
- `Linux` -> `thomas-linux`
- `DOTFILES_HOST` overrides the detected host

Check current source files before assuming old behavior is still true. For OpenCode package issues, read `flake.nix`, `home/editors.nix`, and the relevant host module.

## Symlink Rule

Do not edit live Home Manager outputs under `~/.config/`, `~/.cargo/`, or similar paths when they point into `/nix/store`. Edit the source in this repo or the private overlay, then run:

```sh
bash setup.sh
```

After activation, re-read files before retrying edits. Home Manager can replace symlinks atomically, making previously read content stale.

## Private Flake

The private flake is expected at:

```text
~/.config/dotfiles/flake.nix
```

On first run, `setup.sh` copies `private.example.nix` there and exits unless `DOTFILES_GIT_NAME` and `DOTFILES_GIT_EMAIL` are set.

`setup.sh` uses `--override-input private "path:$HOME/.config/dotfiles"`, so edits in the private flake working tree are used directly. Do not update `flake.lock` or commit private config just to test a private change.

Optional private attrs should be omitted or set to `null`. Empty strings are real string values in Nix and can trip assertions.

## Flake Inputs

Reference inputs by the attribute name in this repo's `flake.nix`, not by the upstream repository name. If the input is named `opencode`, use `inputs.opencode...`, not a guessed name like `inputs.opencode-flake...`.

Branch URLs are pinned by `flake.lock`. Use this to inspect the resolved revision:

```sh
nix flake metadata
```

If a locked input fetch fails, treat it as a fetch/cache/network problem first, not proof that the branch URL is impure or changed.

## macOS Git

On macOS, `/usr/bin/git` can be an Xcode command line tools stub that opens GUI prompts. When diagnosing Nix fetches or using git in a Nix context, prefer Nix-provided git if system git appears broken:

```sh
nix run nixpkgs#git -- --version
```

Use the repo's normal git commands for repository status, diffs, and commits unless there is evidence system git is the blocker.

## Verification

Prefer the repo's existing checks:

```sh
nix flake check
```

Use `nix flake check --all-systems` when the change affects cross-platform evaluation, Home Manager hosts, or Nix library behavior.
