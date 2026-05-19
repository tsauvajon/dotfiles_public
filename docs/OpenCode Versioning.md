# OpenCode Versioning

OpenCode has three independent versioning surfaces in these dotfiles:

- The Nix-managed `opencode` CLI/server binary from `pkgs.opencode`.
- The npm package `@opencode-ai/plugin` installed under `~/.config/opencode` by Bun during Home Manager activation.
- The SQLite database selected by the OpenCode installation channel.

Keep the binary/server version and `@opencode-ai/plugin` version aligned unless
there is a deliberate compatibility test proving a skewed pair works.

## Current Wiring

The binary is installed by `home/editors.nix`:

```nix
home.packages = with pkgs; [
  opencode
];
```

The shared server is managed by `home/opencode-server.nix` and runs the same Nix
package:

```nix
opencodePackage = pkgs.opencode;
opencodeBin = "${opencodePackage}/bin/opencode";
```

Plugin dependencies are declared in `config/opencode/package.json`, rendered to
`~/.config/opencode/package.json`, then installed by `bun install` during
activation.

Useful checks:

```sh
opencode --version
curl --fail --silent http://127.0.0.1:4096/global/health
grep '@opencode-ai/plugin' ~/.config/opencode/bun.lock
node -p 'require(process.env.HOME + "/.config/opencode/node_modules/@opencode-ai/plugin/package.json").version'
```

If `~/.config/opencode/package-lock.json` exists, do not treat it as the active
lock. The active install path is Bun (`bun.lock` + `node_modules`). A stale
`package-lock.json` can report an old plugin version even when Bun installed the
new one.

## Database Selection

OpenCode 1.x stores sessions in SQLite files under
`~/.local/share/opencode/`. The database filename is selected by installation
channel, not by whether OpenCode runs as a CLI or server.

Observed DBs on this machine:

| DB | Meaning |
|---|---|
| `opencode.db` | Legacy / unchannelled DB |
| `opencode-stable.db` | Stable channel DB |
| `opencode-local.db` | Local/dev channel DB |

This is why `opencode -s ses_...` can fail with `Session not found` even when
session JSON blobs exist on disk: the current binary is looking in a different
channel DB.

Diagnose session placement with:

```sh
for db in ~/.local/share/opencode/opencode.db \
          ~/.local/share/opencode/opencode-stable.db \
          ~/.local/share/opencode/opencode-local.db; do
  echo "== $db =="
  sqlite3 "$db" "SELECT id, directory, project_id FROM session WHERE id LIKE 'ses_<prefix>%';"
done
```

Recover by running the binary/channel that owns the session, or by exporting
from the old DB/channel and importing into the active one.

## DB Pinning Knobs

OpenCode supports two relevant environment flags:

| Variable | Effect | Recommendation |
|---|---|---|
| `OPENCODE_DB=opencode-stable.db` | Forces an explicit DB file under `~/.local/share/opencode`, or an absolute DB path if absolute. | Use only if channel drift keeps hiding sessions. |
| `OPENCODE_DISABLE_CHANNEL_DB=1` | Disables channel DB names and uses `opencode.db`. | Avoid here; most current sessions live in `opencode-stable.db`. |

`OPENCODE_DB=opencode-stable.db` can be added to
`programs.opencode.sharedServer.environment` for the shared server, but direct
CLI sessions also need the same environment if they must use the same DB.

Tradeoff: DB pinning prevents accidental channel splits, but removes isolation.
A newer local/dev binary can migrate the shared DB and make rollback to an older
binary risky. Prefer keeping one stable channel on `PATH` before forcing all
channels to one DB.

## Align To 1.14.48

Use this when `pkgs.opencode` is still `1.14.48`.

Change `config/opencode/package.json`:

```json
{
  "dependencies": {
    "@opencode-ai/plugin": "1.14.48"
  }
}
```

Then run:

```sh
bash setup.sh
```

Expected state:

| Surface | Expected |
|---|---|
| `opencode --version` | `1.14.48` |
| shared server health | `1.14.48` |
| `~/.config/opencode/package.json` | `@opencode-ai/plugin` `1.14.48` |
| `~/.config/opencode/bun.lock` | `@opencode-ai/plugin` `1.14.48` |
| DB | `opencode-stable.db` if the Nix package is built with stable channel |

Pros:

- Lowest risk.
- No local Nix package override.
- Keeps the session DB on the current stable channel.
- Avoids binary/plugin API skew.

Cons:

- Gives up newer plugin SDK fixes until nixpkgs updates `pkgs.opencode`.

This is the preferred short-term alignment when stability matters.

## Align To 1.15.5

Use this only if we need OpenCode `1.15.5` before nixpkgs updates.

Keep `config/opencode/package.json` at:

```json
{
  "dependencies": {
    "@opencode-ai/plugin": "1.15.5"
  }
}
```

Overlay `pkgs.opencode` in `flake.nix` so the binary and server also build
`1.15.5`. The nixpkgs package currently fetches
`github:anomalyco/opencode` and has both a source hash and fixed-output
`node_modules` hash, so this takes two hash refreshes.

Overlay shape:

```nix
opencode = prev.opencode.overrideAttrs (finalAttrs: oldAttrs: rec {
  version = "1.15.5";

  src = final.fetchFromGitHub {
    owner = "anomalyco";
    repo = "opencode";
    tag = "v${version}";
    hash = "sha256-...";
  };

  node_modules = oldAttrs.node_modules.overrideAttrs (_: {
    inherit version src;
    outputHash = "sha256-...";
  });

  env = oldAttrs.env // {
    OPENCODE_VERSION = version;
    OPENCODE_CHANNEL = "stable";
  };
});
```

Keep `OPENCODE_CHANNEL = "stable"`. That should preserve use of
`opencode-stable.db`. Building as `local`, `dev`, or another non-stable channel
can move sessions to `opencode-local.db` or another channel-specific DB.

Pros:

- Binary/server and plugin SDK are aligned at latest.
- Still declarative and Home Manager-managed.
- Keeps DB continuity if the channel remains `stable`.

Cons:

- Local Nix override maintenance until nixpkgs catches up.
- Hash churn for source and `node_modules` fixed-output derivations.
- A newer binary may apply DB migrations. Rolling back to `1.14.48` can become
  risky if migrations are not backward-compatible.
- `x86_64-darwin` is already marked bad for `pkgs.opencode`; all-systems checks
  may still fail there.

## Shared Server Restarts

When `setup.sh` runs under an OpenCode agent, Home Manager activation should not
restart the shared OpenCode server immediately. Restarting the server can cut the
transport for the active prompt/tool run.

The dotfiles server module detects OpenCode agent runs (`AGENT=1` plus
OpenCode-specific environment) and defers the restart without updating the hash
marker. Run `bash setup.sh` later from a normal shell to restart safely and mark
the new server inputs as applied.

## Recommendation

Default to the conservative path:

1. Align plugin SDK down to the current Nix binary version.
2. Keep one stable Nix `opencode` on `PATH`.
3. Do not pin `OPENCODE_DB` unless channel drift keeps recurring.
4. If upgrading ahead of nixpkgs, overlay the binary and preserve
   `OPENCODE_CHANNEL = "stable"`.
5. Before and after any binary-channel change, count sessions in each DB and keep
   a backup of `~/.local/share/opencode/*.db*`.

Session-count check:

```sh
for db in ~/.local/share/opencode/opencode.db \
          ~/.local/share/opencode/opencode-stable.db \
          ~/.local/share/opencode/opencode-local.db; do
  name=${db##*/}
  sqlite3 "file:$db?mode=ro" "SELECT '$name', count(*), coalesce(max(time_updated), 0) FROM session;"
done
```
