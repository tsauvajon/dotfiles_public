# Regression guard: every `./<path>.nix` (or `./<path>` directory)
# imported by home/default.nix must resolve to an existing file or
# directory in the source tree.
#
# This protects against two regressions:
#   1. A module is deleted but `home/default.nix` still imports it
#      (the activation build would fail with a "no such file" error
#      that's hard to spot in CI noise).
#   2. A module is renamed without updating the import.
#
# Implementation: parse `home/default.nix` for any `./...nix` /
# `./<dir>` form inside the imports list, then assert each path
# exists relative to the home directory. The check is pure (no IFD).
{ lib }:

let
  home = ./.;
  source = builtins.readFile (home + "/default.nix");

  # Pull every relative path (`./` followed by non-whitespace, ending
  # in either `.nix` or a directory name) out of the file. The leading
  # `./` is included; trailing whitespace and other punctuation are
  # stripped by the regex group.
  matches = builtins.match
    "(.*)" # placate the type checker; we use builtins.split below
    source;

  # `builtins.split` returns a list alternating between non-match
  # strings and match groups (themselves lists). We keep only the
  # match groups whose first element is the captured path.
  parts = builtins.split "\\./([A-Za-z0-9_./-]+)" source;

  importPaths = lib.concatMap (
    p: if builtins.isList p then [ (builtins.elemAt p 0) ] else [ ]
  ) parts;

  # Filter out matches that are not module imports — e.g. a comment
  # like `./bootstrap.nix runs ...`. Real imports always end in either
  # `.nix` or are a directory (no extension). The rendered import
  # block lists each on its own line, so we accept every captured
  # path and rely on `pathExists` to catch typos.
  resolved = map (
    rel:
    let
      candidate = home + "/${rel}";
      candidateNix = home + "/${rel}.nix";
    in
    {
      inherit rel;
      exists = builtins.pathExists candidate || builtins.pathExists candidateNix;
    }
  ) importPaths;

  missing = lib.filter (e: !e.exists) resolved;
in
{
  testImportsResolve = {
    expr = missing;
    expected = [ ];
  };
}
