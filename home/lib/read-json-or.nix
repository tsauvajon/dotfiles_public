# Read a JSON file, returning `default` if `path` is null or does
# not exist. Used to make optional overlay/private files (e.g. the
# OpenCode opencode.json overlay or package.json overlay) absent on a
# fresh machine without forcing every consumer to re-implement the
# null-or-missing dance.
#
# No `{ lib }` wrapper: the helper relies only on builtins and stays a
# bare two-argument function. Call as `readJsonOr path default`.
path: default:
if path == null || !builtins.pathExists path then
  default
else
  builtins.fromJSON (builtins.readFile path)
