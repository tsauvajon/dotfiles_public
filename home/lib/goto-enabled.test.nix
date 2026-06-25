# Unit tests for home/lib/goto-enabled.nix.
{ lib }:

let
  gotoEnabled = import ./goto-enabled.nix { inherit lib; };
in
{
  testNullApiUrlDisables = {
    expr = gotoEnabled {
      apiUrl = null;
      bookmarksFile = "bookmarks.yml";
    };
    expected = false;
  };

  testEmptyApiUrlDisables = {
    expr = gotoEnabled {
      apiUrl = "";
      bookmarksFile = "bookmarks.yml";
    };
    expected = false;
  };

  testNullBookmarksFileDisables = {
    expr = gotoEnabled {
      apiUrl = "http://127.0.0.1:50002";
      bookmarksFile = null;
    };
    expected = false;
  };

  testEmptyBookmarksFileDisables = {
    expr = gotoEnabled {
      apiUrl = "http://127.0.0.1:50002";
      bookmarksFile = "";
    };
    expected = false;
  };

  testStringBookmarksFileEnables = {
    expr = gotoEnabled {
      apiUrl = "http://127.0.0.1:50002";
      bookmarksFile = "bookmarks.yml";
    };
    expected = true;
  };

  testPathBookmarksFileEnables = {
    expr = gotoEnabled {
      apiUrl = "http://127.0.0.1:50002";
      bookmarksFile = ./goto-enabled.test.nix;
    };
    expected = true;
  };
}
