# Concatenate a base file with overlay fragments to produce a single
# output file. Output layout: the base file verbatim, then each
# surviving overlay in byte-sorted filename order, separated by `\n`.
# Fragment dirs are optional. When multiple dirs contain the same
# fragment filename, later dirs win.
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
    map (n: {
      name = n;
      path = dir + "/${n}";
    }) (listFilesIn {
      inherit dir;
      predicate =
        name: type:
        (type == "regular" || type == "symlink")
        && lib.hasPrefix prefix name
        && lib.hasSuffix extension name
        && name != baseName;
    });

  collected = lib.foldl' (
    acc: dir:
    let
      asAttrs = lib.listToAttrs (map (f: lib.nameValuePair f.name f) (fragmentsIn dir));
    in
    acc // asAttrs
  ) { } fragmentDirs;

  fragments = map (name: collected.${name}.path) (builtins.attrNames collected);
in
pkgs.runCommand name { } ''
  cat ${base} > "$out"
  ${lib.concatMapStringsSep "\n" (f: ''
    printf '\n' >> "$out"
    cat ${f} >> "$out"
  '') fragments}
''
