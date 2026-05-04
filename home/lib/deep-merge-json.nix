# Deep-merge a list of JSON-like attrsets, preserving key order.
#
# Matches the Rust `deep_merge_json` semantics from src/merge.rs:
# - For object/object: recursively merge. Base keys come first
#   (preserving base order); overlay-only keys are appended at the end.
#   On a key collision, recurse if both sides are objects, else overlay
#   wins.
# - For everything else: overlay wins.
#
# Note: Nix attrsets are intrinsically sorted by attribute name, so the
# "key order" only matters when the result is serialized via
# `builtins.toJSON`. `builtins.toJSON` itself emits attrs in sorted
# order — so byte-equivalence with the Rust tool's pretty-printed
# `serde_json` output is approximate; structural equivalence (same
# keys, same values) is exact.
{ lib }:

let
  deepMerge =
    base: overlay:
    if builtins.isAttrs base && builtins.isAttrs overlay then
      let
        baseKeys = builtins.attrNames base;
        overlayKeys = builtins.attrNames overlay;
        commonOverlayOnly = lib.filter (k: !(builtins.elem k baseKeys)) overlayKeys;
        mergedBase = lib.listToAttrs (
          map (k: {
            name = k;
            value = if builtins.hasAttr k overlay then deepMerge base.${k} overlay.${k} else base.${k};
          }) baseKeys
        );
        addedFromOverlay = lib.listToAttrs (
          map (k: {
            name = k;
            value = overlay.${k};
          }) commonOverlayOnly
        );
      in
      mergedBase // addedFromOverlay
    else
      overlay;
in
{
  inherit deepMerge;

  # Convenience: deep-merge a list of values left-to-right.
  deepMergeAll = lib.foldl' deepMerge { };
}
