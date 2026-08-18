# Cranelift for Rust Builds

[Cranelift](https://cranelift.dev/) is an alternative code-generation backend
for Rust. It often compiles debug builds faster than LLVM, at the cost of less
optimized generated code and support for fewer targets and compiler features.
It is most useful for local development builds and edit-compile-run loops. It
can also reduce test compilation time, but panic semantics and slower generated
code can make some test suites incompatible or slower overall. Keep production
and performance-sensitive builds on LLVM unless they have been validated
separately.

## Requirements

Cargo's named codegen-backend support and rustc's Cranelift backend are unstable
and require nightly Rust. The backend must match the exact rustc nightly because
it uses rustc's internal ABI.

With rustup, install one nightly and its matching component:

```sh
rustup toolchain install nightly
rustup component add rustc-codegen-cranelift-preview --toolchain nightly
```

The component is not published for every nightly and target. If installation
fails, choose a nightly where the component is available rather than combining
a backend from one nightly with rustc from another.

For toolchains installed by Nix, a system package manager, or a custom build,
rustc and the Cranelift backend must match exactly. Cargo must be a nightly that
supports the `codegen-backend` feature, but it does not share rustc's internal
backend ABI. Named backend lookup expects the backend library in rustc's sysroot
under the host's `codegen-backends` directory; low-level
`rustc -Zcodegen-backend=<path>` can load a backend from an explicit path.

## Project Configuration

To enable Cranelift for development profiles in one project, add this to
`.cargo/config.toml` at the workspace root:

```toml
[unstable]
codegen-backend = true

[profile.dev]
codegen-backend = "cranelift"
```

Run the project with nightly Cargo:

```sh
cargo +nightly build
cargo +nightly run
cargo +nightly test
```

The `+nightly` selector is provided by rustup. With another toolchain manager,
run the selected nightly Cargo directly.

Do not put the unstable profile setting in a global Cargo config if stable Cargo
is also used on the machine. Stable Cargo still reads the global file and
rejects the nightly-only setting.

As an alternative to `.cargo/config.toml`, a workspace can opt into the feature
in its root `Cargo.toml`. `cargo-features` must be the first manifest key:

```toml
cargo-features = ["codegen-backend"]

[profile.dev]
codegen-backend = "cranelift"
```

Both project forms require nightly Cargo. The manifest form travels with the
project; `.cargo/config.toml` lookup depends on the directory from which Cargo
is invoked.

For a one-off build without changing a config file, in a POSIX shell:

```sh
CARGO_PROFILE_DEV_CODEGEN_BACKEND=cranelift \
  cargo +nightly -Zcodegen-backend build
```

The upstream Cranelift documentation uses this Cargo environment key for
`profile.dev.codegen-backend`; `-Zcodegen-backend` enables the unstable Cargo
feature for that invocation. The equivalent PowerShell commands are:

```powershell
$env:CARGO_PROFILE_DEV_CODEGEN_BACKEND = "cranelift"
cargo +nightly -Zcodegen-backend build
Remove-Item Env:CARGO_PROFILE_DEV_CODEGEN_BACKEND
```

Cargo's command-line config override is another option:

```sh
cargo +nightly -Zcodegen-backend \
  --config 'profile.dev.codegen-backend="cranelift"' build
```

## Profile Behavior

Setting only `profile.dev.codegen-backend` produces this default policy:

| Command or profile | Backend |
| --- | --- |
| `cargo build` and `cargo run` | Cranelift |
| `cargo test` | Cranelift because `test` inherits `dev`; see panic limitations below |
| Custom profiles inheriting `dev` | Cranelift |
| `cargo build --release` | LLVM |
| `cargo bench` | LLVM because `bench` inherits `release` |
| Default `cargo install` | LLVM |
| `cargo install --debug` | Cranelift because it uses `dev` |

`cargo check` does not normally generate final machine code for the selected
package, so it is not a useful test that Cranelift can build and link the
program. Build scripts, proc macros, and their dependencies may still require
host-side code generation.

## Mixed-Backend Workspaces

Cargo can compile selected packages with LLVM while the rest of a development
build uses Cranelift. This is useful when one dependency requires an intrinsic,
ABI, crate type, or compiler option that Cranelift does not support.

Add a package override beside the project-level configuration:

```toml
[profile.dev.package.problematic-package]
codegen-backend = "llvm"
```

Cargo then builds one dependency graph containing artifacts from both backends;
it does not rerun the entire build with LLVM. Package overrides can also target
a package ID specification when multiple versions of one dependency are in the
graph. Keep the override as narrow as possible and document why that package
needs LLVM.

Cargo does not automatically retry failed Cranelift compilation with LLVM. To
switch the whole dev build explicitly in a POSIX shell:

```sh
CARGO_PROFILE_DEV_CODEGEN_BACKEND=llvm cargo +nightly build
```

In PowerShell:

```powershell
$env:CARGO_PROFILE_DEV_CODEGEN_BACKEND = "llvm"
cargo +nightly build
Remove-Item Env:CARGO_PROFILE_DEV_CODEGEN_BACKEND
```

The same override can be supplied without an environment variable:

```sh
cargo +nightly --config 'profile.dev.codegen-backend="llvm"' build
```

## Known Limitations

Validate a representative workspace before making Cranelift the default:

- Official component availability depends on the nightly, host, and target.
  Upstream currently distributes it for x86-64 and AArch64 Linux and macOS,
  plus x86-64 Windows. Other supported hosts may require building the backend
  from source; check the upstream platform matrix before choosing a workflow.
- Cross-compilation targets may not be supported even when the host is.
- Panic unwinding is experimental and is not supported on Windows or macOS;
  Cranelift enables `panic=abort` by default. Code using `catch_unwind`, panic
  recovery, or `#[should_panic]` tests can behave differently or fail.
- SIMD, architecture intrinsics, and some ABIs remain less complete than LLVM.
- Sanitizers, coverage instrumentation, LTO, profiling, and compiler plugins may
  require LLVM.
- Build scripts and proc macros can expose host-side backend incompatibilities.
- The standard library remains the distributed LLVM-built standard library.
  Rebuilding it is a separate nightly `build-std` workflow.
- Cranelift output is intended for compile speed, not production runtime
  performance.

Environment variables belonging to a dependency's build script are not general
Cranelift requirements. Add such workarounds only to projects and dependency
versions that demonstrate the corresponding failure.

## Verification

Use a fresh target directory so Cargo must invoke rustc instead of reusing an
existing artifact. In a POSIX shell:

```sh
CARGO_TARGET_DIR=target-cranelift-verify cargo +nightly build -vv
```

In PowerShell:

```powershell
$env:CARGO_TARGET_DIR = "target-cranelift-verify"
cargo +nightly build -vv
Remove-Item Env:CARGO_TARGET_DIR
```

A successful verification has all of these properties:

1. Cargo's verbose rustc command contains `codegen-backend=cranelift`.
2. The command performs `--emit=...link`, not only metadata or analysis.
3. The resulting executable or test binary runs successfully.

Also verify LLVM fallback and release behavior:

```sh
CARGO_TARGET_DIR=target-llvm-verify \
  CARGO_PROFILE_DEV_CODEGEN_BACKEND=llvm \
  cargo +nightly build -vv

CARGO_TARGET_DIR=target-release-verify cargo +nightly build --release -vv
```

PowerShell equivalents:

```powershell
$env:CARGO_TARGET_DIR = "target-llvm-verify"
$env:CARGO_PROFILE_DEV_CODEGEN_BACKEND = "llvm"
cargo +nightly build -vv

$env:CARGO_TARGET_DIR = "target-release-verify"
Remove-Item Env:CARGO_PROFILE_DEV_CODEGEN_BACKEND
cargo +nightly build --release -vv
Remove-Item Env:CARGO_TARGET_DIR
```

The first verbose command should contain `codegen-backend=llvm`. The release
command should not select Cranelift when only `profile.dev` is configured.

Do not rely only on a component listing or `cargo check`: they prove that a
backend may be installed or that code type-checks, not that Cranelift generated
and linked the executable.

## Sources

- [Cargo unstable codegen backend](https://doc.rust-lang.org/nightly/cargo/reference/unstable.html#codegen-backend)
- [Cargo build-performance guidance](https://doc.rust-lang.org/cargo/guide/build-performance.html#use-an-alternative-codegen-backend)
- [Cargo profiles](https://doc.rust-lang.org/cargo/reference/profiles.html)
- [rustc codegen backend flag](https://doc.rust-lang.org/nightly/unstable-book/compiler-flags/codegen-backend.html)
- [rustc_codegen_cranelift](https://github.com/rust-lang/rustc_codegen_cranelift)
