---
name: idiomatic-rust
description: Guide for writing idiomatic Rust. Use when authoring, reviewing, or refactoring Rust code.
compatibility: opencode
metadata:
  status: stable
  version: "1.0.0"
---

# Idiomatic Rust

Style and structure rules to apply when writing or reviewing Rust. This skill is a style layer - it does not override project-specific conventions. Before applying any rule, read `Cargo.toml` and the surrounding module to confirm the change fits existing patterns.

`Before` snippets intentionally show discouraged code and are not expected to be lint-clean. `After` snippets should compile in suitable surrounding context and satisfy the project's hardened lint policy, including `-D warnings` and missing-docs checks.

## Principles

### A. Types over strings

#### 1. Strong types over `String`

Wrap domain values in a newtype. Never pass naked `String` for things like IDs, names, paths, or resource identifiers.

Before:
```rust
fn load_profile(user: String, workspace: String) -> Profile { ... }
```

After:
```rust
struct UserId(u64);
struct WorkspaceName(String);

fn load_profile(user: &UserId, workspace: &WorkspaceName) -> Profile {
    Profile::load(user, workspace)
}
```

#### 2. Enums over string parsing

Closed sets are enums. Do not `match s.as_str()`.

Before:
```rust
match format.as_str() {
    "json" => export_json(),
    "csv"  => export_csv(),
    _      => panic!("bad format"),
}
```

After:
```rust
#[derive(strum::EnumString)]
#[strum(serialize_all = "lowercase")]
enum ExportFormat {
    Json,
    Csv,
}

fn export(format: &ExportFormat) -> Document {
    match format {
        ExportFormat::Json => export_json(),
        ExportFormat::Csv => export_csv(),
    }
}
```

#### 3. `strum` / `serde` derives over inline conversions

Reach for derives before hand-rolling `FromStr`, `Display`, or `try_from` impls.

Before:
```rust
impl FromStr for Role {
    type Err = Error;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s {
            "admin"  => Ok(Role::Admin),
            "viewer" => Ok(Role::Viewer),
            _        => Err(Error::BadRole),
        }
    }
}
```

After:
```rust
#[derive(strum::EnumString, strum::Display)]
#[strum(serialize_all = "lowercase")]
enum Role {
    Admin,
    Viewer,
}
```

#### 4. `impl Display` over ad-hoc string building

If the same representation is built in more than one place, implement `Display` once.

Before:
```rust
let key = format!("{}:{}:{}", workspace.id, project.slug, job.id);
log::info!("cache miss for {}:{}:{}", workspace.id, project.slug, job.id);
```

After:
```rust
impl std::fmt::Display for CacheKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}:{}:{}", self.workspace, self.project, self.job)
    }
}

fn log_cache_miss(key: &CacheKey) {
    log::info!("cache miss for {key}");
}
```

### B. Express intent and separate concerns

#### 5. No code comments - prefer strong types, names, and extracted functions

A comment describing *what* the next line does is a signal to rename a variable, introduce a newtype, or extract a function. The code should read the same as the comment would. Keep comments only for *why* something non-obvious is done: business rules, workarounds, links to tickets.

Before:
```rust
// check whether this upload exceeds the workspace quota
if upload_size > 10_000 && !workspace.has_extra_storage {
    return Err(Error::QuotaExceeded);
}

// convert bytes to megabytes for display
let display = bytes as f64 / 1_000_000.0;
```

After:
```rust
fn validate_upload(upload_size: UploadSize, workspace: &Workspace) -> Result<(), Error> {
    if exceeds_workspace_quota(upload_size, workspace) {
        return Err(Error::QuotaExceeded);
    }

    Ok(())
}

fn display_size(bytes: Bytes) -> Megabytes {
    Megabytes::from(bytes)
}
```

#### 6. Prefer named iterator and collection operations

Use an iterator or collection operation when it expresses the objective more directly. Keep an explicit loop when it makes state, control flow, side effects, or error handling clearer.

Before:
```rust
fn search<'a>(query: &str, contents: &'a str) -> Vec<&'a str> {
    let mut results = Vec::new();

    for line in contents.lines() {
        if line.contains(query) {
            results.push(line);
        }
    }

    results
}
```

After:
```rust
fn search<'a>(query: &str, contents: &'a str) -> Vec<&'a str> {
    contents
        .lines()
        .filter(|line| line.contains(query))
        .collect()
}
```

#### 7. Long functions doing multiple things - extract helpers

If a function has distinct steps (validate, fetch, format), each step becomes its own function. Validation failures return `Err` immediately, and the top-level function reads as a short summary of what it does.

Before:
```rust
fn handle(req: Request) -> Result<Response, Error> {
    if req.user.is_empty() {
        return Err(Error::InvalidUser);
    }
    if req.workspace.is_empty() {
        return Err(Error::InvalidWorkspace);
    }

    let user = db.get(&req.user)?;
    let profile = directory.profile(&req.workspace, &user)?;

    Ok(Response::ok(profile.to_string()))
}
```

After:
```rust
fn handle(req: Request) -> Result<Response, Error> {
    let req = validate(req)?;
    let profile = fetch_profile(&req)?;
    Ok(Response::ok(profile.to_string()))
}
```

#### 8. Big files with section separators - split into modules

If a file is large enough that you want `// --- foo ---` or `// ===== foo =====` banners inside it to find your way around, that is the signal to split the file into sibling module files. Think about the natural seams (parsing, dispatch, types, errors) and give each one its own file.

Before:
```rust
// src/proxy.rs
// ===== parsing =====
fn parse_request(...) { ... }
fn parse_header(...)  { ... }

// ===== dispatch =====
fn dispatch(...) { ... }

// ===== errors =====
pub enum ProxyError { ... }
```

After:
```rust
// src/proxy/mod.rs
mod dispatch;
mod errors;
mod parsing;

use self::{dispatch::dispatch, errors::ProxyError};
use crate::Response;

fn proxy(input: &[u8]) -> Result<Response, ProxyError> {
    let request = parsing::request(input)?;
    dispatch(request)
}
```
```rust
// src/proxy/parsing.rs
use super::ProxyError;

pub(super) fn request(input: &[u8]) -> Result<(u8, &[u8]), ProxyError> {
    let (header, body) = input.split_first().ok_or(ProxyError::MissingHeader)?;
    Ok((*header, body))
}
```
```rust
// src/proxy/dispatch.rs
use super::{ProxyError, Response};

pub(super) fn dispatch(request: (u8, &[u8])) -> Result<Response, ProxyError> {
    let (header, body) = request;
    Response::from_parts(header, body).ok_or(ProxyError::InvalidResponse)
}
```
```rust
// src/proxy/errors.rs
#[derive(Debug)]
pub(super) enum ProxyError {
    MissingHeader,
    InvalidResponse,
}
```

### C. Control flow

#### 9. Nested `if` / nested `for` - early return or extract

Flatten with guard clauses, `let ... else`, `?`, or by lifting the inner body into a helper. Keep the happy path aligned to the left.

Before:
```rust
fn process(opt: Option<Req>) -> Result<Res, Error> {
    if let Some(req) = opt {
        if req.is_valid() {
            if let Some(user) = lookup(&req.user) {
                return Ok(Res::new(user, req));
            }
        }
    }
    Err(Error::Skip)
}
```

After:
```rust
fn process(opt: Option<Req>) -> Result<Res, Error> {
    let Some(req) = opt else {
        return Err(Error::Skip)
    };
    if !req.is_valid() {
        return Err(Error::Skip)
    }
    let Some(user) = lookup(&req.user) else {
        return Err(Error::Skip)
    };

    Ok(Res::new(user, req))
}
```

### D. Boundaries and API design

#### 10. Boundary types - strong types, custom `Deserialize`

At I/O edges (HTTP bodies, queue messages, DB rows, env vars) prefer strong types with a `Deserialize` or `TryFrom<String>` impl over carrying `String` through the code.

Before:
```rust
#[derive(Deserialize)]
struct Body { workspace: String, user: String }

fn handler(b: Body) {
    if !is_known_workspace(&b.workspace) { return; }
    // ... b.workspace and b.user flow through everything as String
}
```

After:
```rust
#[derive(serde::Deserialize)]
struct Body {
    workspace: WorkspaceName,
    user: UserId,
}

fn handler(body: &Body) -> Response {
    Response::for_user(&body.workspace, &body.user)
}
```

#### 11. Stable framework re-exports for framework-only types

Before adding a direct dependency, check whether the framework exposes a documented, stable re-export of the type. Prefer that re-export when the type is used only through the framework, so the crate stays aligned with the framework's version. Keep the direct dependency when the type is also used independently or the re-export is not a documented, stable part of the framework's public API.

Before:
```toml
# Cargo.toml
[dependencies]
axum = "0.8"
http = "1"  # only used for StatusCode and HeaderMap
```
```rust
use http::{HeaderMap, StatusCode};
```

After:
```toml
# Cargo.toml — drop the redundant `http` dependency.
[dependencies]
axum = "0.8"
```
```rust
use axum::http::{HeaderMap, StatusCode};

fn status_for(headers: &HeaderMap) -> StatusCode {
    if headers.is_empty() {
        return StatusCode::NO_CONTENT;
    }

    StatusCode::OK
}
```

#### 12. Avoid positional arguments

For functions with 3+ parameters, or any two of the same type, or any `bool` / `Option<_>`, use a parameter struct or newtypes. Use the builder pattern for optional config.

Before:
```rust
fn send(from: String, to: String, amount: u64, dry_run: bool, retry: bool) { ... }

send(a, b, 100, true, false); // which bool is which?
```

After:
```rust
struct SendArgs {
    from: Address,
    to: Address,
    amount: Amount,
    dry_run: bool,
    retry: bool,
}

fn send(args: &SendArgs) -> Result<Receipt, Error> {
    execute(args)
}

fn send_payment(payment: Payment) -> Result<Receipt, Error> {
    send(&SendArgs {
        from: payment.from,
        to: payment.to,
        amount: payment.amount,
        dry_run: true,
        retry: false,
    })
}
```

#### 13. `SomeType::from(x)` over `x.into()`

Make the target type explicit at the call site. `.into()` hides what is being produced behind type inference, forcing the reader to look at the binding's annotation, the function signature, or the `?`'s error type to know what conversion runs. `T::from(x)` puts the answer where the conversion happens.

Before:
```rust
let port: Port = config.port.into();
let body: RequestBody = payload.into();
return Err(err.into());
```

After:
```rust
fn build_request(config: &Config, payload: Payload) -> Result<Request, ApiError> {
    let port = Port::from(config.port);
    let body = RequestBody::from(payload);
    Request::try_new(port, body).map_err(ApiError::from)
}
```

## Review checklist

Run this pass against existing Rust. Cite rule numbers in review comments.

- [ ] `pub fn foo(a: String, b: String)` where `a` / `b` have distinct meanings -> rule 1
- [ ] `match s.as_str() { ... }` over a closed set -> rule 2
- [ ] Hand-rolled `FromStr` / `Display` for a plain enum -> rule 3
- [ ] `format!` building a domain representation at a call site -> rule 4
- [ ] Comment describing *what* the next line or block does -> rule 5
- [ ] Filtering and collection loop whose objective is clearer as an iterator pipeline -> rule 6
- [ ] Function with distinct steps (validate / fetch / format) in one body -> rule 7
- [ ] `// --- foo ---` or `// ===== foo =====` banners inside a single file -> rule 8
- [ ] `if let Some(x) = a { if let Some(y) = b { ... } }` -> rule 9
- [ ] `Deserialize` struct carrying raw `String` for a validated domain -> rule 10
- [ ] New direct dependency for a type used only through a framework that has a documented, stable re-export -> rule 11
- [ ] `fn(bool, bool, ...)`, `fn(String, String, ...)`, or 3+ positional params -> rule 12
- [ ] `x.into()` where the target type is not visible at the call site -> rule 13

## Application order

When refactoring an existing file, apply rules in this order so each step compiles cleanly:

1. Introduce strong types and enums (rules 1, 2).
2. Add `Display` / `Deserialize` / derive impls (rules 3, 4, 10).
3. Drop explanatory comments, use clear iterator operations, extract helpers, and split big files into modules (rules 5, 6, 7, 8).
4. Flatten control flow (rule 9).
5. Swap positional calls for named / struct args last - this touches call sites (rule 12).
6. Replace `.into()` with `T::from(x)` at call sites where the target type is not obvious (rule 13).
7. Drop framework-only redundant dependencies last (rule 11), after the code compiles on the documented, stable re-export.

## Constraints

- Do not introduce new crates without first checking `cargo tree` and existing re-exports.
- Do not mix style refactors with behavior changes in the same commit.
- Preserve existing project conventions when they conflict with these rules.
- Never disable tests to satisfy a style rule.
- Follow the repository's `/pre-commit` skill and run relevant tests before committing.
