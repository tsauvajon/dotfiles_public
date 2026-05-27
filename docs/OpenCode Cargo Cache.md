# OpenCode Cargo Cache

OpenCode shell commands on macOS automatically isolate Cargo build output per
top-level OpenCode session while sharing compiler artifacts through `kache`, with
`sccache` kept as the fallback wrapper.

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

When `kache` is on `PATH`, the plugin ensures these variables are set unless
they were already inherited from the OpenCode server process or hook output:

- `RUSTC_WRAPPER=<path-to-kache>`
- `KACHE_FALLBACK=<path-to-sccache>` when the selected wrapper is kache and
  `sccache` is also on `PATH`

If `kache` is missing but `sccache` is on `PATH`, it preserves the older
sccache-only behavior and sets:

- `RUSTC_WRAPPER=<path-to-sccache>`

When `sccache` is on `PATH`, it also sets:

- `SCCACHE_DIR=$HOME/.cache/sccache`
- `SCCACHE_CACHE_SIZE=100G`

Managed `zsh` and `fish` sessions set `KACHE_FALLBACK=sccache`,
`SCCACHE_DIR=$HOME/.cache/sccache`, and `SCCACHE_CACHE_SIZE=100G` on all
platforms. The same values are also exported through Home Manager session
variables so the managed OpenCode shared server's launchd/systemd environment
sees them after activation and restart. This lets manual `nix develop` subshells
and OpenCode share the same fallback cache directory and disk budget.
Kache accepts both the bare fallback command name used by shell env and the
absolute fallback path used by the OpenCode plugin.

Rust compiler caching comes from the managed Cargo config at
`~/.cargo/config.toml`, which sets `build.rustc-wrapper = "kache"`. Home Manager
also writes `~/.config/kache/config.toml` with `[cache] fallback = "sccache"`
and manages the `kache daemon run` user service through launchd on macOS and
systemd user services on Linux. Native builds that use `cc-rs` also use the
Cargo wrapper, so `CC` and `CXX` intentionally remain direct compiler values
from Cargo config or the toolchain defaults.

## Native Compiler Guardrails

Do not set `CC` or `CXX` to `kache clang`, `sccache clang`, `sccache cc`,
`sccache c++`, or custom cache-wrapper scripts. Keep them as direct compiler
paths from the toolchain, Cargo config, or the repository's Nix shell. `cc-rs`
can already use Cargo's `RUSTC_WRAPPER` for native C/C++ compilation; wrapping
the native compiler as well can produce commands like `sccache sccache-clang ...`
and fail.

The OpenCode plugin warns once per process if the inherited OpenCode server
environment has `CC` or `CXX` containing `kache` or `sccache`, but it does not
rewrite those variables. Rewriting them in the plugin could break
repository-specific Nix or SDK compiler choices. If native compilation looks
cache-related, diagnose with `KACHE_DISABLED=1` or `SCCACHE_DISABLE=1` rather
than changing `CC` or `CXX` to wrapper commands.

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
KACHE_DISABLED=1 opencode
SCCACHE_DISABLE=1 opencode
```

For the managed shared server, set opt-out variables in the server environment
and restart the server so the plugin process inherits them.
`KACHE_DISABLED=1` disables kache itself, while `SCCACHE_DISABLE=1` only disables
the sccache fallback. Neither disables `CARGO_TARGET_DIR` isolation.

After activation, use `kache doctor` to check the wrapper and daemon setup. If
the `sccache` daemon has started because kache delegated a compile to its
fallback, doctor should report it as the fallback wrapper rather than stale
competing sccache setup. Do not run `kache init` against the managed Cargo
config; Home Manager owns the Cargo wrapper, kache config file, and daemon
service.

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
Use commands that are expected to exit successfully in the benchmark environment;
for example, install any private package credentials first or benchmark a narrower
workspace slice. The script still completes all phases and writes `results.tsv`
when commands fail, but it prints warnings and exits non-zero if any result row
has a non-zero `exit_code`.
