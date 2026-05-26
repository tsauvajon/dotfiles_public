# OpenCode Cargo Cache

OpenCode shell commands on macOS automatically isolate Cargo build output per
top-level OpenCode session while sharing compiler artifacts through `sccache`.

The managed plugin lives at `config/opencode/plugins/cargo-build-env.ts` and is
autoloaded from `~/.config/opencode/plugins/`. It only runs on Darwin; Linux is
currently a no-op until the setup is validated there.

When a shell command starts inside a Cargo package or workspace on macOS, the
plugin always sets this variable unless it is already present in the OpenCode
server process environment or in the shell hook output:

- `CARGO_TARGET_DIR=<cargo-root>/target/opencode/<session-id>`

For subagents, `<session-id>` is the root parent session id. This lets all
subagents spawned by one task reuse the same Cargo target artifacts while still
keeping unrelated top-level OpenCode sessions isolated from each other.

When `sccache` is on `PATH`, it also sets:

- `RUSTC_WRAPPER=<path-to-sccache>`
- `SCCACHE_DIR=$HOME/.cache/sccache`
- `SCCACHE_CACHE_SIZE=100G`

Managed `zsh` and `fish` sessions set `SCCACHE_DIR=$HOME/.cache/sccache` and
`SCCACHE_CACHE_SIZE=100G` on all platforms. The same values are also exported
through Home Manager session variables so the managed OpenCode shared server's
launchd/systemd environment sees them after activation and restart. This lets
manual `nix develop` subshells and OpenCode share the same cache directory and
disk budget. Rust compiler caching comes from the managed Cargo config at
`~/.cargo/config.toml`, which sets `build.rustc-wrapper = "sccache"`. Native
builds that use `cc-rs` also use that wrapper, so `CC` and `CXX` intentionally
remain direct compiler values from Cargo config or the toolchain defaults.

## Native Compiler Guardrails

Do not set `CC` or `CXX` to `sccache clang`, `sccache cc`, `sccache c++`, or a
custom `sccache-*` wrapper script. Keep them as direct compiler paths from the
toolchain, Cargo config, or the repository's Nix shell. `cc-rs` can already use
Cargo's `RUSTC_WRAPPER=sccache` for native C/C++ compilation; wrapping the native
compiler as well can produce commands like `sccache sccache-clang ...` and fail.

The OpenCode plugin warns once per process if the inherited OpenCode server
environment has `CC` or `CXX` containing `sccache`, but it does not rewrite those
variables. Rewriting them in the plugin could break repository-specific Nix or
SDK compiler choices. If native compilation looks cache-related, diagnose with
`SCCACHE_DISABLE=1` rather than changing `CC` or `CXX` to wrapper commands.

When OpenCode is attached to the managed shared server, the session id usually
comes from the server hook input and there is no `OPENCODE_RUN_ID` prefix. Direct
OpenCode launches may include an additional run-id prefix. If OpenCode provides
a child session id, the plugin asks the OpenCode session API for its parent chain
and uses the root parent id. If any lookup fails, it falls back to the current
session id without caching that failed lookup, so a later shell command can retry.
If OpenCode ever omits both identifiers, the plugin falls back to
`pid-<server-pid>` so it still avoids the workspace's default `target/`.

To opt out for a specific OpenCode launch, set the desired variable before
starting OpenCode, for example:

```sh
CARGO_TARGET_DIR=target opencode
SCCACHE_DISABLE=1 opencode
```

For the managed shared server, set opt-out variables in the server environment
and restart the server so the plugin process inherits them.
`SCCACHE_DISABLE=1` only disables sccache itself; it does not disable
`CARGO_TARGET_DIR` isolation.

Per-root-session target directories are intentionally left under
`target/opencode/`; remove that directory when stale session builds take too
much disk space. A typical cleanup command from a workspace root is:

```sh
find target/opencode -mindepth 1 -maxdepth 1 -mtime +14 -exec rm -rf {} +
```

## Benchmarking sccache and kache

Use `scripts/cargo-cache-benchmark.sh` to compare fresh per-agent target
directories backed by plain `sccache` against `kache` with
`KACHE_FALLBACK=sccache`. The script is opt-in, works against one or more repos,
and keeps all generated targets and caches under its output directory instead of
using the repo-local `target/` directory.

The script preflights each `--repo` with `cargo locate-project --workspace`, so
pass the actual Cargo workspace root or a child directory inside that workspace.
Use separate runs for the command profiles you care about; these five reflect the
Cargo commands Thomas runs most often in shell history:

```sh
./scripts/cargo-cache-benchmark.sh \
  --repo wallet=/tmp/hello \
  --repo other=/path/to/other/cargo/workspace \
  --agent-count 4 \
  -- cargo clippy --workspace --all-targets --all-features -- -D warnings

./scripts/cargo-cache-benchmark.sh \
  --repo wallet=/tmp/hello \
  --repo other=/path/to/other/cargo/workspace \
  --agent-count 4 \
  -- cargo run --release

./scripts/cargo-cache-benchmark.sh \
  --repo wallet=/tmp/hello \
  --repo other=/path/to/other/cargo/workspace \
  --agent-count 4 \
  -- cargo test --workspace

./scripts/cargo-cache-benchmark.sh \
  --repo wallet=/tmp/hello \
  --repo other=/path/to/other/cargo/workspace \
  --agent-count 4 \
  -- cargo clippy --workspace --all-targets

./scripts/cargo-cache-benchmark.sh \
  --repo wallet=/tmp/hello \
  --repo other=/path/to/other/cargo/workspace \
  --agent-count 4 \
  -- cargo check --workspace
```

Only use the `cargo run --release` profile when the workspace binary exits on its
own or when you provide safe arguments after `--`; otherwise prefer `cargo build
--release` for a compile-only comparison.

Each repo and mode runs three phases: cold cache and cold target,
warm cache with fresh per-agent targets, and warm cache with target reuse. Results
are written to `results.tsv` with wall time, `Compiling ...` line counts, file
lock waits, target/cache sizes, and `sccache --show-stats` counters. The script
sets `CARGO_INCREMENTAL=0` for both modes so the comparison focuses on target and
compiler-cache behavior; it does not set, unset, or rewrite `CC` or `CXX`.
