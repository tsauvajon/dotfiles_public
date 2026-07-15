{ lib }:

let
  source = builtins.readFile ./flake.nix;
  normalizedSource = lib.replaceStrings [ " " "\n" "\t" ] [ "" "" "" ] source;
  guardedApiForCursorOutput = ''//lib.optionalAttrs(system=="aarch64-darwin"){inherit(pkgs)api-for-cursor;}'';
in
{
  testApiForCursorPackagesAndChecksAreAarch64DarwinOnly = {
    expr = builtins.length (lib.splitString guardedApiForCursorOutput normalizedSource) == 3;
    expected = true;
  };
}
