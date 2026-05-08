# List entries in a directory by name, sorted in byte order (LC_ALL=C),
# filtered by an optional `predicate`. Returns an empty list if the
# directory does not exist — matches the "optional private overlay"
# convention used across this repo.
#
# Why not just call `builtins.readDir` everywhere? Three call sites
# (`concat-files.nix`, `concat-toml-files.nix`, `opencode-merge.nix`,
# plus `programs/task.nix`) had grown nearly identical
# `pathExists`-guarded `readDir + filterAttrs + attrNames` blocks.
# This helper centralises the pattern so each caller only has to
# express its filename predicate.
#
# Args:
#   dir         — path to scan (path or coercible to path)
#   predicate   — `name -> type -> bool`, called with the filename and
#                 the `builtins.readDir` type ("regular", "directory",
#                 "symlink", ...). Defaults to "any regular file or
#                 symlink", which matches the most common case across
#                 callers (private overlays often symlink fragments
#                 from a sibling source).
#
# Returns: list of filenames (strings), sorted by `builtins.attrNames`
# (byte order, LC_ALL=C). Combine with `dir + "/${name}"` at the call
# site to get absolute paths.
{ lib }:

{
  dir,
  predicate ? (_: type: type == "regular" || type == "symlink"),
}:

if !builtins.pathExists dir then
  [ ]
else
  let
    entries = builtins.readDir dir;
    accepted = lib.filterAttrs predicate entries;
  in
  # `builtins.attrNames` already returns names in byte-sorted order.
  builtins.attrNames accepted
