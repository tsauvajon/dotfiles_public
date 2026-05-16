# OpenCode Permission Globs

OpenCode permission patterns are not filesystem globs. The pinned OpenCode
source uses `packages/opencode/src/util/wildcard.ts`, where `*` becomes regex
`.*` and `?` becomes `.`.

Practical consequences:

- `*` crosses `/` path separators.
- `**` has no special meaning and is redundant.
- Matching is anchored to the whole string.
- Last matching rule wins.
- Config patterns expand `~/`, `~`, and `$HOME` before matching.
- Bash permissions match command strings, not filesystem paths.
- Bash patterns ending in ` *` also match the bare command, so `ls *` matches `ls`.

For OpenCode filesystem permissions, prefer single-star path patterns such as
`~/dev/*`, `/tmp/*`, and `/private/var/*/opencode/*`.

## Watcher ignore patterns (different engine)

The watcher (`@parcel/watcher`) uses a **different** glob engine from
permissions — minimatch-style globs where `**` is meaningful and matches
across directory boundaries. Same for the internal `FileIgnore.PATTERNS`
in `packages/opencode/src/file/ignore.ts` which delegates to
`@opencode-ai/core/util/glob`.

So `**/node_modules/**` in `opencode.watcher.json` is correct; do not
convert watcher patterns to single-star form.
