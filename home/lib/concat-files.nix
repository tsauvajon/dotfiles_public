# Concatenate a base file (optional) with overlay fragments from one
# or more directories. Used to build OpenCode's AGENTS.md from a public
# base + private rules overlays.
#
# - `base`: optional path to a base file, prepended verbatim.
# - `fragmentDirs`: list of directories to scan for fragments. Within
#   each directory, regular files are sorted by filename (byte order,
#   matching `LC_ALL=C` sort) and concatenated. Directories are processed
#   in the order given, so a single overlay dir is the typical case.
# - `headerTemplate`: prepended before each fragment. The literal string
#   `%FILENAME%` is replaced with the fragment's filename.
# - `substitutions`: attrset of {placeholder = value;} applied to the
#   final concatenated string. Used for `__DOTFILES_PATH__`-style
#   placeholders the Rust tool used to substitute.
#
# Empty files are skipped. Fragments are separated by `\n\n`.
{ lib }:

{
  base ? null,
  fragmentDirs ? [ ],
  headerTemplate ? "# Rules overlay: %FILENAME%\n\n",
  substitutions ? { },
}:

let
  baseContent = if base != null then builtins.readFile base else "";

  # Sort regular files (including symlinks to files) in `dir` by
  # filename bytes — LC_ALL=C order. Returns `[ { name; path; } ]` or
  # `[]` if `dir` does not exist. Symlinks are accepted so private
  # rules overlays can chain (e.g. an overlay that symlinks to the
  # public AGENTS.md).
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

  fragments = lib.concatLists (map regularFilesIn fragmentDirs);

  # Read each file and drop empties — matching the Rust check on
  # `metadata.len() == 0`.
  fragmentsWithContent = lib.filter (f: f.content != "") (
    map (f: {
      inherit (f) name;
      content = builtins.readFile f.path;
    }) fragments
  );

  rendered = lib.foldl' (
    acc: f:
    let
      header = lib.replaceStrings [ "%FILENAME%" ] [ f.name ] headerTemplate;
      separator = if acc == "" then "" else "\n\n";
    in
    acc + separator + header + f.content
  ) baseContent fragmentsWithContent;

  substituted = lib.replaceStrings (builtins.attrNames substitutions) (
    builtins.attrValues substitutions
  ) rendered;
in
substituted
