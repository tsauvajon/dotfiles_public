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
  rustModuleSource = builtins.readFile (home + "/rust.nix");

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

  testKacheUsesGracefulBoundedStop = {
    expr =
      (lib.hasInfix ''
        ExecStop = "''${kacheBin} daemon stop";
      '' rustModuleSource)
      && (lib.hasInfix ''
        KillSignal = "SIGKILL";
      '' rustModuleSource)
      && (lib.hasInfix ''
        TimeoutStopSec = "5s";
      '' rustModuleSource)
      && (lib.hasInfix "HOME=\${lib.escapeShellArg config.home.homeDirectory} KACHE_CONFIG=" rustModuleSource)
      && (lib.hasInfix ''
        ''${kacheBin} daemon stop >/dev/null 2>&1 || true
      '' rustModuleSource)
      && (lib.hasInfix ''
        KACHE_DAEMON_IDLE_TIMEOUT = "0";
      '' rustModuleSource)
      && (lib.hasInfix ''
        kacheLocalMaxSize = "300GiB";
      '' rustModuleSource)
      && (lib.hasInfix ''
        KACHE_MAX_SIZE = kacheLocalMaxSize;
      '' rustModuleSource)
      && (lib.hasInfix ''
        local_max_size = "''${kacheLocalMaxSize}"
      '' rustModuleSource);
    expected = true;
  };
}
