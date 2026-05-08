# Unit tests for home/lib/list-files-in.nix.
#
# Returns an attrset of `lib.runTests`-compatible cases. Fixtures live
# in the sibling `list-files-in.test/` directory so they are pure
# paths inside the flake source tree (no IFD).
{ lib }:

let
  listFilesIn = import ./list-files-in.nix { inherit lib; };
in
{
  testMissingDir = {
    # Non-existent dirs are silently skipped (matches the "optional
    # private overlay" convention used across the repo).
    expr = listFilesIn { dir = /nonexistent/list-files-in-test; };
    expected = [ ];
  };

  testEmptyDir = {
    # `.gitkeep` is a regular file, so the default predicate keeps it.
    # The empty fixture only exists to exercise the path-exists branch.
    expr = listFilesIn { dir = ./list-files-in.test/empty; };
    expected = [ ".gitkeep" ];
  };

  testDefaultPredicateExcludesDirs = {
    # The mixed fixture contains three files and one subdirectory.
    # Default predicate keeps regular files (and symlinks) only, so
    # `subdir/` must not appear in the result.
    expr = listFilesIn { dir = ./list-files-in.test/mixed; };
    expected = [
      "00.md"
      "01.toml"
      "02.toml"
    ];
  };

  testCustomPredicate = {
    # Filter by extension. Only `.toml` files survive.
    expr = listFilesIn {
      dir = ./list-files-in.test/mixed;
      predicate = name: type: (type == "regular") && lib.hasSuffix ".toml" name;
    };
    expected = [
      "01.toml"
      "02.toml"
    ];
  };

  testSortOrderIsByteOrder = {
    # `builtins.attrNames` returns names in byte-sorted order, so
    # `00.md` precedes `01.toml` precedes `02.toml`.
    expr = listFilesIn { dir = ./list-files-in.test/mixed; };
    expected = [
      "00.md"
      "01.toml"
      "02.toml"
    ];
  };
}
