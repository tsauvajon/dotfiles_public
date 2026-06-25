# Deep-merge JSON-like attrsets using nixpkgs' recursiveUpdate
# contract: attrset-vs-attrset collisions recurse; arrays, nulls, and
# scalar values are replaced wholesale by the later value.
{ lib }:

{
  deepMerge = lib.recursiveUpdate;

  # Convenience: deep-merge a list of values left-to-right.
  deepMergeAll = lib.foldl' lib.recursiveUpdate { };
}
