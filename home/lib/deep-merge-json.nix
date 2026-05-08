# Deep-merge a list of JSON-like attrsets.
#
# Semantics:
# - For object/object: recursively merge. On a key collision, recurse
#   if both sides are objects, else overlay wins.
# - For everything else (arrays, primitives): overlay wins; arrays are
#   replaced wholesale, never concatenated.
#
# Nix attrsets are intrinsically sorted by attribute name, and
# `builtins.toJSON` emits them in that sorted order, so the resulting
# JSON has stable byte-level output regardless of how the inputs were
# constructed.
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
