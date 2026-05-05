# Concatenate fragment files from one or more directories, sorted by
# filename across all sources. Used to build OpenCode's AGENTS.md from
# public + private rules dirs.
#
# - `fragmentDirs`: list of directories to scan. Regular files (and
#   symlinks to files) are collected from every directory and merged
#   into a single set keyed by filename. On filename collision, later
#   directories in the list win — pass `[ public private ]` so that
#   the private overlay overrides the public source. The combined set
#   is then sorted by filename in byte order (LC_ALL=C).
# - `headerTemplate`: prepended before each fragment. The literal
#   string `%FILENAME%` is replaced with the fragment's filename.
#
# Empty files are skipped. Fragments are separated by `\n\n`.
{ lib }:

{
  fragmentDirs ? [ ],
  headerTemplate ? "# Rules overlay: %FILENAME%\n\n",
}:

let
  # Sort regular files (including symlinks to files) in `dir` by
  # filename bytes — LC_ALL=C order. Returns `[ { name; path; } ]` or
  # `[]` if `dir` does not exist. Symlinks are accepted so private
  # overlays may chain (e.g. an overlay that symlinks to a sibling).
  regularFilesIn =
    dir:
    if !builtins.pathExists dir then
      [ ]
    else
      let
        entries = builtins.readDir dir;
        accepted = lib.filterAttrs (_: type: type == "regular" || type == "symlink") entries;
        names = lib.sort (a: b: a < b) (builtins.attrNames accepted);
      in
      map (name: {
        inherit name;
        path = dir + "/${name}";
      }) names;

  # Collect entries from every dir, then collapse to a name-keyed
  # attrset where later dirs override earlier ones on filename
  # collision (private wins when passed last).
  collected = lib.foldl' (
    acc: dir:
    let
      entries = regularFilesIn dir;
      asAttrs = lib.listToAttrs (map (e: lib.nameValuePair e.name e) entries);
    in
    acc // asAttrs
  ) { } fragmentDirs;

  # Sort the merged set by filename in byte order so public and
  # private fragments interleave naturally.
  sortedNames = lib.sort (a: b: a < b) (builtins.attrNames collected);
  fragments = map (name: collected.${name}) sortedNames;

  # Read each file and drop empties.
  fragmentsWithContent = lib.filter (f: f.content != "") (
    map (f: {
      inherit (f) name;
      content = builtins.readFile f.path;
    }) fragments
  );
in
lib.foldl' (
  acc: f:
  let
    header = lib.replaceStrings [ "%FILENAME%" ] [ f.name ] headerTemplate;
    separator = if acc == "" then "" else "\n\n";
  in
  acc + separator + header + f.content
) "" fragmentsWithContent
