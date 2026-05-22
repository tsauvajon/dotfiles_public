# OpenCode Cargo Cache

OpenCode shell commands on macOS automatically isolate Cargo build output per
OpenCode session while sharing compiler artifacts through `sccache`.

The managed plugin lives at `config/opencode/plugins/cargo-build-env.ts` and is
autoloaded from `~/.config/opencode/plugins/`. It only runs on Darwin; Linux is
currently a no-op until the setup is validated there.

When a shell command starts inside a Cargo package or workspace on macOS, the
plugin always sets this variable unless it is already present in the OpenCode
server process environment or in the shell hook output:

- `CARGO_TARGET_DIR=<cargo-root>/target/opencode/<session-id>`

When `sccache` is on `PATH`, it also sets:

- `RUSTC_WRAPPER=<path-to-sccache>`
- `SCCACHE_DIR=$HOME/.cache/sccache`

When both native wrapper commands are on `PATH` and native caching is not
disabled, it also sets:

- `CC=<path-to-sccache-clang>`
- `CXX=<path-to-sccache-clang++>`

The `sccache-clang*` wrappers are Home Manager-installed macOS helpers that
resolve the active Xcode or Command Line Tools compiler through `xcrun` and call
it through `sccache`. They avoid multi-word `CC` / `CXX` values, which some
native build tools cannot execute directly.

Managed `zsh` and `fish` sessions set `SCCACHE_DIR=$HOME/.cache/sccache` on all
platforms. On macOS, they set `CC` and `CXX` to the Home Manager profile wrapper
paths when those variables are not already set, both wrappers are installed, and
native caching is not disabled. This lets manual `nix develop` subshells inherit
the same Rust and native compiler cache settings as OpenCode.

`CC` and `CXX` are only injected by the OpenCode plugin when both wrappers are
already on `PATH` and native caching is not disabled; managed shells use the
absolute Home Manager profile paths. These variables apply to all native compiler
invocations in that process tree, not only Cargo build scripts. To disable just
this native layer, launch OpenCode or start a managed shell with
`OPENCODE_CARGO_NATIVE_CACHE=0`; changing it in an existing shell does not unset
already-exported `CC` or `CXX`.

The Darwin Cargo config keeps its existing Xcode `CC` fallback. Managed shell or
OpenCode `CC` values take precedence, while opt-out and unmanaged shells keep the
previous direct-clang behavior.

The native layer also requires the shared OpenCode server process to inherit a
`PATH` containing the Home Manager profile bin where the wrapper commands live.
The wrappers require a working macOS developer toolchain resolvable through
`/usr/bin/xcrun`.

When OpenCode is attached to the managed shared server, the session id usually
comes from the server hook input and there is no `OPENCODE_RUN_ID` prefix. Direct
OpenCode launches may include an additional run-id prefix. If OpenCode ever omits
both identifiers, the plugin falls back to `pid-<server-pid>` so it still avoids
the workspace's default `target/`.

To opt out for a specific OpenCode launch, set the desired variable before
starting OpenCode, for example:

```sh
CARGO_TARGET_DIR=target opencode
OPENCODE_CARGO_NATIVE_CACHE=0 opencode
SCCACHE_DISABLE=1 opencode
```

For the managed shared server, set opt-out variables in the server environment
and restart the server so the plugin process inherits them.
`SCCACHE_DISABLE=1` only disables sccache itself; it does not disable
`CARGO_TARGET_DIR` isolation.

Per-session target directories are intentionally left under
`target/opencode/`; remove that directory when stale session builds take too
much disk space. A typical cleanup command from a workspace root is:

```sh
find target/opencode -mindepth 1 -maxdepth 1 -mtime +14 -exec rm -rf {} +
```
