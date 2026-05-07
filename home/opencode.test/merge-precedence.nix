# Tests the 4-tier merge precedence in `mkMergedOpencodeJson`.
#
# Tiers (later wins on key collision):
#   1. publicRoot/opencode.*.json
#   2. importsDirs[*]/opencode.*.json
#   3. privateOpencodeDir/opencode.*.json
#   4. privateConfigFile (single JSON file)
#
# Fixtures live under ./fixtures/{public,private,imports/sample}/.
{ lib }:

let
  inherit (import ../lib/opencode-merge.nix { inherit lib; }) mkMergedOpencodeJson;

  merged = mkMergedOpencodeJson {
    publicRoot = ./fixtures/public;
    importsDirs = [ ./fixtures/imports/sample ];
    privateOpencodeDir = ./fixtures/private;
    privateConfigFile = ./fixtures/private/opencode.json;
  };
in
{
  testOverlayWinsModel = {
    # Tier 4 (private overlay) sets model="private-overlay-wins".
    # Tier 3 fragment sets model="private-fragment-default".
    # Tier 1 fragment sets model="public-default".
    # Final value must come from tier 4.
    expr = merged.model;
    expected = "private-overlay-wins";
  };

  testPublicOnlyKeySurvives = {
    # Keys that exist only in public must pass through unchanged.
    expr = merged.publicOnly;
    expected = "stays";
  };

  testPrivateFragmentKeyAdded = {
    # Keys present only in private fragment (tier 3) must be added.
    expr = merged.privateOnly;
    expected = "added";
  };

  testWithinPublicTierLaterFilenameWins = {
    # public/opencode.aaa.json sets withinTier="from-aaa-public".
    # public/opencode.zzz.json sets withinTier="from-zzz-public".
    # `aaa` < `zzz` in byte order, so zzz is processed last and wins.
    expr = merged.withinTier;
    expected = "from-zzz-public";
  };

  testPrivateFragmentBeatsPublicFragment = {
    # public/opencode.permission.bash.json sets bash="ask".
    # private/opencode.permission.bash.json sets bash="allow".
    # Private fragment (tier 3) beats public fragment (tier 1).
    expr = merged.permission.bash;
    expected = "allow";
  };

  testImportFragmentContributesDisjointKey = {
    # Tier 2 (imports) sets mcp.sample.url; no other tier touches it,
    # so the import value must survive the merge.
    expr = merged.mcp.sample.url;
    expected = "https://example/mcp";
  };

  testPrivateFragmentBeatsImportFragment = {
    # imports/sample/opencode.mcp.json sets mcp.sample.type="remote".
    # private/opencode.mcp.json sets mcp.sample.type="private-wins".
    # Tier 3 (private fragment) must beat tier 2 (import) on collision.
    expr = merged.mcp.sample.type;
    expected = "private-wins";
  };

  testOverlayKeyAdded = {
    # Tier 4 also adds disjoint keys (share="disabled").
    expr = merged.share;
    expected = "disabled";
  };
}
