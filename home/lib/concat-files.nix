# Concatenate fragment files from one or more directories, sorted by
# filename across all sources. Used to build OpenCode's AGENTS.md from
# public + private rules dirs.
#
# - `fragmentDirs`: list of directories to scan. Regular files (and
#   symlinks to files) are collected from every directory and merged
#   into a single set keyed by filename after empty files are skipped
#   within each source directory. On filename collision, later
#   directories in the list win — pass `[ public private ]` so that
#   a non-empty private overlay overrides the public source. Empty
#   overlays cannot delete non-empty earlier fragments. The combined
#   set is then sorted by filename in byte order (LC_ALL=C).
# - `headerTemplate`: prepended before each fragment. The literal
#   string `%FILENAME%` is replaced with the fragment's filename.
#
# Empty files are skipped before collision resolution. Fragments are
# separated by `\n\n`.
{ lib }:

{
  fragmentDirs ? [ ],
  headerTemplate ? "# Rules overlay: %FILENAME%\n\n",
}:

let
  listFilesIn = import ./list-files-in.nix { inherit lib; };

  # Sort regular files (including symlinks to files) in `dir` by
  # filename bytes — LC_ALL=C order. Returns `[ { name; path; } ]` or
  # `[]` if `dir` does not exist. Symlinks are accepted so private
  # overlays may chain (e.g. an overlay that symlinks to a sibling).
  regularFilesIn =
    dir:
    map (name: {
      inherit name;
      path = dir + "/${name}";
    }) (listFilesIn { inherit dir; });

  # Collect non-empty entries from every dir, then collapse to a
  # name-keyed attrset where later dirs override earlier ones on
  # filename collision (private wins when passed last). Empty overlay
  # files are filtered before this merge so they cannot shadow a
  # non-empty base fragment.
  collected = lib.foldl' (
    acc: dir:
    let
      entries = lib.filter (f: f.content != "") (
        map (f: {
          inherit (f) name path;
          content = builtins.readFile f.path;
        }) (regularFilesIn dir)
      );
      asAttrs = lib.listToAttrs (map (e: lib.nameValuePair e.name e) entries);
    in
    acc // asAttrs
  ) { } fragmentDirs;

  # `builtins.attrNames` returns names in byte-sorted order, which is
  # the interleave we want across public and private fragments.
  sortedNames = builtins.attrNames collected;
  fragments = map (name: collected.${name}) sortedNames;

in
lib.foldl' (
  acc: f:
  let
    header = lib.replaceStrings [ "%FILENAME%" ] [ f.name ] headerTemplate;
    separator = if acc == "" then "" else "\n\n";
  in
  acc + separator + header + f.content
) "" fragments
