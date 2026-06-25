# Unit tests for home/lib/read-json-or.nix.
#
# Returns an attrset of `lib.runTests`-compatible cases.
{ lib }:

let
  readJsonOr = import ./read-json-or.nix;
  default = {
    fallback = true;
  };
in
{
  testNullPathReturnsDefault = {
    expr = readJsonOr null default;
    expected = default;
  };

  testMissingPathReturnsDefault = {
    expr = readJsonOr /nonexistent/read-json-or-test/sample.json default;
    expected = default;
  };

  testExistingJsonIsParsed = {
    expr = readJsonOr ./read-json-or.test/sample.json default;
    expected = {
      name = "sample";
      nested.enabled = true;
      values = [
        1
        2
      ];
    };
  };
}
