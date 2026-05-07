# Tests within-tier filename ordering for `mkMergedOpencodeJson`.
#
# Within a single tier, fragment files are processed in byte-sorted
# filename order (LC_ALL=C). Later filenames win on key collision.
# Fixture: three fragments setting the same key "key" plus disjoint
# marker keys (aaaOnly, mmmOnly, zzzOnly).
{ lib }:

let
  inherit (import ../lib/opencode-merge.nix { inherit lib; }) mkMergedOpencodeJson;

  merged = mkMergedOpencodeJson {
    publicRoot = ./fixtures-sort;
  };
in
{
  testLastFilenameWinsOnCollision = {
    # All three fragments set "key". With aaa < mmm < zzz in byte
    # order, zzz is processed last and its value must win.
    expr = merged.key;
    expected = "from-zzz";
  };

  testEarlierFilenameKeysSurvive = {
    # Disjoint keys from earlier-processed fragments must be retained
    # rather than dropped during the merge.
    expr = merged.aaaOnly;
    expected = true;
  };

  testMiddleFilenameKeysSurvive = {
    expr = merged.mmmOnly;
    expected = true;
  };

  testLastFilenameKeysSurvive = {
    expr = merged.zzzOnly;
    expected = true;
  };
}
