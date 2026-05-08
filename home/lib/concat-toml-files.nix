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
  listFilesIn = import ./list-files-in.nix { inherit lib; };

  baseName = baseNameOf base;

  fragmentsIn =
    dir:
    map (n: dir + "/${n}") (listFilesIn {
      inherit dir;
      predicate =
        name: type:
        (type == "regular" || type == "symlink")
        && lib.hasPrefix prefix name
        && lib.hasSuffix extension name
        && name != baseName;
    });

  fragments = lib.concatLists (map fragmentsIn fragmentDirs);
in
pkgs.runCommand name { } ''
  cat ${base} > "$out"
  ${lib.concatMapStringsSep "\n" (f: ''
    printf '\n' >> "$out"
    cat ${f} >> "$out"
  '') fragments}
''
