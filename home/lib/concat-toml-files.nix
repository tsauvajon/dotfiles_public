# Concatenate a base file with overlay fragments to produce a single
# output file, matching the Rust setup tool's `merge_overlay` semantics
# byte-for-byte (base verbatim, then for each overlay: a `\n` then the
# overlay content).
#
# Used for cargo / aerospace / alacritty where the base config plus
# platform/private fragments are stitched together. Attribute-level
# TOML merging would be cleaner but reorders keys and may flatten
# structures the user has carefully laid out, so we stick with text
# concat.
{ pkgs, lib }:

{
  name,
  base,
  fragmentDirs ? [ ],
  prefix ? "",
  extension ? ".toml",
}:

let
  baseName = baseNameOf base;

  fragmentsIn =
    dir:
    if !builtins.pathExists dir then
      [ ]
    else
      let
        entries = builtins.readDir dir;
        accepted = lib.filterAttrs (
          name: type:
          (type == "regular" || type == "symlink")
          && lib.hasPrefix prefix name
          && lib.hasSuffix extension name
          && name != baseName
        ) entries;
        names = lib.sort (a: b: a < b) (builtins.attrNames accepted);
      in
      map (n: dir + "/${n}") names;

  fragments = lib.concatLists (map fragmentsIn fragmentDirs);
in
pkgs.runCommand name { } ''
  cat ${toString base} > "$out"
  ${lib.concatMapStringsSep "\n" (f: ''
    printf '\n' >> "$out"
    cat ${toString f} >> "$out"
  '') fragments}
''
