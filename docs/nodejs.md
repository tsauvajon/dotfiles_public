# Node.js And Bun

This dotfiles setup installs Bun globally through Home Manager. It does not
install a global Node.js version manager or global Node.js runtime by default.

Use Bun first for Svelte frontend work. If a project later needs Node.js, add it
locally for that project with Nix.

## Installed Globally

- `bun`

Not installed globally:

- `node`
- `npm`
- `npx`
- `pnpm`
- `yarn`
- `asdf`, `mise`, `nvm`, or `fnm` for Node.js version management

## New Svelte Project

```sh
bun create svelte@latest my-app
cd my-app
bun install
bun run dev
```

Build the project with:

```sh
bun run build
```

Run one-off package binaries with:

```sh
bunx <package>
```

## Existing Repo

Prefer the package manager implied by the repo:

- `bun.lock` or `bun.lockb`: use Bun.
- `package-lock.json`: the repo likely expects npm and Node.js.
- `pnpm-lock.yaml`: the repo likely expects pnpm and Node.js.
- `yarn.lock`: the repo likely expects Yarn and Node.js.
- `flake.nix`: prefer `nix develop` if the repo provides a dev shell.

For a Bun project:

```sh
bun install
bun run dev
bun run build
```

## Project-Specific Node.js

If a repo needs Node.js, keep it local to that repo instead of adding a global
runtime immediately.

For a temporary shell:

```sh
nix shell nixpkgs#nodejs_24
```

For a repo that should always use Node.js, add a local `flake.nix` with a dev
shell and enter it with:

```sh
nix develop
```

That keeps the global setup Bun-only while still allowing projects to pin their
own Node.js version when needed.
