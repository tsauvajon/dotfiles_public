# Unit tests for home/lib/concat-files.nix.
#
# Returns an attrset of `lib.runTests`-compatible cases. Fixtures live
# in the sibling `concat-files.test/` directory so they are pure paths
# inside the flake source tree (no IFD).
{ lib }:

let
  concatFiles = import ./concat-files.nix { inherit lib; };
in
{
  testEmptyList = {
    expr = concatFiles { fragmentDirs = [ ]; };
    expected = "";
  };

  testNonExistentDir = {
    # Non-existent dirs are silently skipped (used for optional private
    # overlays). `/nonexistent` is guaranteed not to exist in /nix/store.
    expr = concatFiles { fragmentDirs = [ /nonexistent/concat-files-test ]; };
    expected = "";
  };

  testSingleFile = {
    expr = concatFiles { fragmentDirs = [ ./concat-files.test/single ]; };
    expected = "# Rules overlay: 01.md\n\nsingle content\n";
  };

  testMultipleFilesSorted = {
    # Files are sorted by filename (byte order). 01 < 02 < 03.
    expr = concatFiles { fragmentDirs = [ ./concat-files.test/multi ]; };
    expected =
      "# Rules overlay: 01.md\n\nfirst content\n"
      + "\n\n"
      + "# Rules overlay: 02.md\n\nsecond content\n"
      + "\n\n"
      + "# Rules overlay: 03.md\n\nthird content\n";
  };

  testCollisionPrivateWins = {
    # Two dirs sharing `b.md`. Private is passed last, so its content
    # overrides public's. Expected output: a.md (public) + b.md
    # (private content) + c.md (private), all sorted by filename.
    expr = concatFiles {
      fragmentDirs = [
        ./concat-files.test/collide-public
        ./concat-files.test/collide-private
      ];
    };
    expected =
      "# Rules overlay: a.md\n\npublic-a\n"
      + "\n\n"
      + "# Rules overlay: b.md\n\nprivate-b\n"
      + "\n\n"
      + "# Rules overlay: c.md\n\nprivate-c\n";
  };

  testCustomHeaderTemplate = {
    expr = concatFiles {
      fragmentDirs = [ ./concat-files.test/single ];
      headerTemplate = "<<%FILENAME%>>\n";
    };
    expected = "<<01.md>>\nsingle content\n";
  };

  testEmptyFilesAreSkipped = {
    # `empty.md` has zero bytes; per the function contract it is
    # filtered out. Only `full.md` should appear in the output.
    expr = concatFiles { fragmentDirs = [ ./concat-files.test/with-empty ]; };
    expected = "# Rules overlay: full.md\n\nfull content\n";
  };
}
