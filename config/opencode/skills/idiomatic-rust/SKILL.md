---
name: idiomatic-rust
description: Guide for writing idiomatic Rust. Use when authoring, reviewing, or refactoring Rust code to apply project conventions - strong types over strings, enum parsing, impl Display, extracting functions and modules, early returns, boundary types, re-exports, and named arguments.
compatibility: opencode
metadata:
  status: experimental
  version: "0.1.0"
---

# Idiomatic Rust

Style and structure rules to apply when writing or reviewing Rust. This skill is a style layer - it does not override project-specific conventions. Before applying any rule, read `Cargo.toml` and the surrounding module to confirm the change fits existing patterns.

## Principles

### A. Types over strings

#### 1. Strong types over `String`

Wrap domain values in a newtype. Never pass naked `String` for things like IDs, names, paths, or chain identifiers.

Before:
```rust
fn fetch_balance(user: String, chain: String) -> Balance { ... }
```

After:
```rust
pub struct UserId(u64);
pub struct ChainName(String);

fn fetch_balance(user: UserId, chain: ChainName) -> Balance { ... }
```

#### 2. Enums over string parsing

Closed sets are enums. Do not `match s.as_str()`.

Before:
```rust
match env.as_str() {
    "prod" => deploy_prod(),
    "uat"  => deploy_uat(),
    _      => panic!("bad env"),
}
```

After:
```rust
#[derive(strum::EnumString)]
#[strum(serialize_all = "lowercase")]
pub enum Env { Prod, Uat }

match env {
    Env::Prod => deploy_prod(),
    Env::Uat  => deploy_uat(),
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
pub enum Role { Admin, Viewer }
```

#### 4. `impl Display` over ad-hoc string building

If the same representation is built in more than one place, implement `Display` once.

Before:
```rust
let key = format!("{}:{}:{}", tenant.id, chain.name, account.id);
log::info!("cache miss for {}:{}:{}", tenant.id, chain.name, account.id);
```

After:
```rust
impl fmt::Display for CacheKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}:{}:{}", self.tenant, self.chain, self.account)
    }
}

let key = CacheKey { tenant, chain, account };
log::info!("cache miss for {key}");
```

### B. Extract aggressively

#### 5. Inline calculations - extract a function or a strong type

`for` loops with counters, accumulators, or running state hide logic. Lift them into a named function, or a small type with a method.

Before:
```rust
let mut total = 0;
let mut count = 0;
for tx in txs {
    if tx.is_settled() {
        total += tx.amount;
        count += 1;
    }
}
let avg = total / count;
```

After:
```rust
fn settled_average(txs: &[Tx]) -> u64 {
    let settled: Vec<_> = txs.iter().filter(|t| t.is_settled()).collect();
    settled.iter().map(|t| t.amount).sum::<u64>() / settled.len() as u64
}
```

#### 6. Functions with section comments - extract a function

`// --- validate ---` inside a fn body means the fn is doing more than one thing. Each section becomes its own function.

Before:
```rust
fn handle(req: Request) -> Response {
    // --- validate ---
    if req.user.is_empty() { return Response::bad(); }
    if req.chain.is_empty() { return Response::bad(); }

    // --- fetch ---
    let acct = db.get(&req.user)?;
    let bal  = chain_client.balance(&req.chain, &acct)?;

    // --- format ---
    Response::ok(format!("{bal}"))
}
```

After:
```rust
fn handle(req: Request) -> Response {
    let req = validate(req)?;
    let bal = fetch_balance(&req)?;
    Response::ok(format!("{bal}"))
}
```

#### 7. Modules with section delimiters - extract a module

If you are writing `// ===== parsing =====` inside `mod foo`, parsing wants to be its own module.

Before:
```rust
mod proxy {
    // ===== parsing =====
    fn parse_request(...) { ... }
    fn parse_header(...)  { ... }

    // ===== dispatch =====
    fn dispatch(...)      { ... }
}
```

After:
```rust
mod proxy {
    mod parsing  { pub fn request(...) { ... } pub fn header(...) { ... } }
    mod dispatch { pub fn dispatch(...) { ... } }
}
```

### C. Control flow

#### 8. Nested `if` / nested `for` - early return or extract

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
    let Some(req) = opt else { return Err(Error::Skip); };
    if !req.is_valid() { return Err(Error::Skip); }
    let Some(user) = lookup(&req.user) else { return Err(Error::Skip); };
    Ok(Res::new(user, req))
}
```

### D. Boundaries and API design

#### 9. Boundary types - strong types, custom `Deserialize`

At I/O edges (HTTP bodies, Kafka messages, DB rows, env vars) prefer strong types with a `Deserialize` or `TryFrom<String>` impl over carrying `String` through the code.

Before:
```rust
#[derive(Deserialize)]
struct Body { chain: String, user: String }

fn handler(b: Body) {
    if !is_known_chain(&b.chain) { return; }
    // ... b.chain and b.user flow through everything as String
}
```

After:
```rust
#[derive(Deserialize)]
struct Body {
    chain: ChainName, // ChainName has a Deserialize that validates
    user:  UserId,
}

fn handler(b: Body) {
    // invalid chains and users were rejected at deserialize time
}
```

#### 10. Re-exports over new dependencies

Before adding a crate, check `cargo tree` and the re-exports of crates already in the tree. Common sources: `anyhow`, `tokio`, `serde`, workspace-internal prelude crates.

Before:
```toml
# Cargo.toml
[dependencies]
parking_lot = "0.12"  # tokio already re-exports sync primitives
```

After:
```rust
use tokio::sync::Mutex;
```

#### 11. Avoid positional arguments

For functions with 3+ parameters, or any two of the same type, or any `bool` / `Option<_>`, use a parameter struct or newtypes. Use the builder pattern for optional config.

Before:
```rust
fn send(from: String, to: String, amount: u64, dry_run: bool, retry: bool) { ... }

send(a, b, 100, true, false); // which bool is which?
```

After:
```rust
pub struct SendArgs {
    pub from:    Address,
    pub to:      Address,
    pub amount:  Amount,
    pub dry_run: bool,
    pub retry:   bool,
}

fn send(args: SendArgs) { ... }

send(SendArgs { from, to, amount, dry_run: true, retry: false });
```

## Review checklist

Run this pass against existing Rust. Cite rule numbers in review comments.

- [ ] `pub fn foo(a: String, b: String)` where `a` / `b` have distinct meanings -> rule 1
- [ ] `match s.as_str() { ... }` over a closed set -> rule 2
- [ ] Hand-rolled `FromStr` / `Display` for a plain enum -> rule 3
- [ ] `format!` building a domain representation at a call site -> rule 4
- [ ] `for` loop mutating counters/accumulators outside the loop -> rule 5
- [ ] `// --- step N ---` or `// validate` inside a function body -> rule 6
- [ ] `// ===== section =====` inside a module -> rule 7
- [ ] `if let Some(x) = a { if let Some(y) = b { ... } }` -> rule 8
- [ ] `Deserialize` struct carrying raw `String` for a validated domain -> rule 9
- [ ] New direct dependency where a transitive re-export exists -> rule 10
- [ ] `fn(bool, bool, ...)`, `fn(String, String, ...)`, or 3+ positional params -> rule 11

## Application order

When refactoring an existing file, apply rules in this order so each step compiles cleanly:

1. Introduce strong types and enums (rules 1, 2).
2. Add `Display` / `Deserialize` / derive impls (rules 3, 4, 9).
3. Extract helper functions and modules (rules 5, 6, 7).
4. Flatten control flow (rule 8).
5. Swap positional calls for named / struct args last - this touches call sites (rule 11).
6. Drop redundant dependencies last (rule 10), after the code compiles on the re-export.

## Constraints

- Do not introduce new crates without first checking `cargo tree` and existing re-exports.
- Do not mix style refactors with behavior changes in the same commit.
- Preserve existing project conventions when they conflict with these rules.
- Never disable tests to satisfy a style rule.
- Run `cargo fmt`, `cargo clippy --all-targets --all-features -- -D warnings`, and `cargo test` before committing.
