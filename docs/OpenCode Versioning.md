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

## Current Version Pin

These dotfiles currently pin OpenCode to `1.15.11` in `flake.nix` via
`opencodePin`, which holds the OpenCode version, source hash, and fixed-output
`nodeModulesHash`.

The pin overrides `pkgs.opencode`, so both the installed CLI in
`home/editors.nix` and the shared server in `home/opencode-server.nix` use the
same Nix package.

Keep `config/opencode/package.json` aligned with the same version:

```json
{
  "dependencies": {
    "@opencode-ai/plugin": "1.15.11"
  }
}
```

The flake check `opencode-version-alignment` fails if `pkgs.opencode.version`,
`opencodePin.version`, and `@opencode-ai/plugin` drift apart.

The override preserves `OPENCODE_CHANNEL = "stable"`. That should preserve use
of `opencode-stable.db`. Building as `local`, `dev`, or another non-stable
channel can move sessions to `opencode-local.db` or another channel-specific DB.

For `x86_64-darwin`, nixpkgs marks OpenCode as a bad platform because Bun can
fail on Intel CPUs without AVX. The local overlay removes only OpenCode's
`x86_64-darwin` bad-platform marker when evaluating the `x86_64-darwin` package
set. It does not enable unsupported packages globally.

## Updating OpenCode

When bumping OpenCode, update all versioned surfaces together:

1. Change `opencodePin.version` in `flake.nix`.
2. Refresh `opencodePin.srcHash` for `github:anomalyco/opencode` tag `v<version>`.
3. Refresh `opencodePin.nodeModulesHash` for the package's fixed-output `node_modules` derivation.
4. Change `@opencode-ai/plugin` in `config/opencode/package.json` to the same version.
5. Run `nix flake check` or at least the current system's `opencode-version-alignment` check.
6. Run `bash setup.sh` so Home Manager links the new binary/config and Bun refreshes the plugin install.

If `~/.config/dotfiles/opencode/package.json` exists, keep its
`@opencode-ai/plugin` override aligned too. Private package overlays win over
the public package manifest during the Home Manager merge.

A newer binary may apply DB migrations. Before and after a binary-channel
change, count sessions in each DB and keep a backup of
`~/.local/share/opencode/*.db*`.

## Shared Server Restarts

When `setup.sh` runs under an OpenCode agent, Home Manager activation should not
restart the shared OpenCode server immediately. Restarting the server can cut the
transport for the active prompt/tool run.

The dotfiles server module detects OpenCode agent runs (`AGENT=1` plus
OpenCode-specific environment) and defers the restart without updating the hash
marker. Run `bash setup.sh` later from a normal shell to restart safely and mark
the new server inputs as applied.

## Recommendation

Keep the current pinned path boring:

1. Keep the Nix binary/server and plugin SDK on the same version.
2. Keep one stable Nix `opencode` on `PATH`.
3. Preserve `OPENCODE_CHANNEL = "stable"` in the Nix override.
4. Do not pin `OPENCODE_DB` unless channel drift keeps recurring.
5. Before and after any binary-channel change, count sessions in each DB and keep a backup of `~/.local/share/opencode/*.db*`.

Session-count check:

```sh
for db in ~/.local/share/opencode/opencode.db \
          ~/.local/share/opencode/opencode-stable.db \
          ~/.local/share/opencode/opencode-local.db; do
  name=${db##*/}
  sqlite3 "file:$db?mode=ro" "SELECT '$name', count(*), coalesce(max(time_updated), 0) FROM session;"
done
```
