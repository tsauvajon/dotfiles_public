# Tests that `mkMergedOpencodeJson` and `mkAgentsContent` behave
# correctly when no private overlay is provided. The placeholder
# private flake (and minimal user flakes) leave every private path
# null, so this is the most common configuration on a fresh machine.
{ lib }:

let
  inherit (import ../lib/opencode-merge.nix { inherit lib; })
    mkMergedOpencodeJson
    mkAgentsContent
    ;

  mergedJsonNoPrivate = mkMergedOpencodeJson {
    publicRoot = ./fixtures/public;
    # privateOpencodeDir and privateConfigFile both default to null.
  };

  mergedJsonNullPaths = mkMergedOpencodeJson {
    publicRoot = ./fixtures/public;
    privateOpencodeDir = null;
    privateConfigFile = null;
  };

  agentsNoPrivate = mkAgentsContent {
    rulesMode = "merged";
    publicRulesDir = ./fixtures/public/rules;
    # importRulesDirs defaults to []; privateRulesDir defaults to null.
  };
in
{
  testJsonHasPublicValuesWithoutPrivate = {
    expr = mergedJsonNoPrivate.model;
    expected = "public-default";
  };

  testJsonHasNoPrivateOnlyKey = {
    # privateOnly is set only by tier 3 (private fragment). With no
    # private dir, the key must not appear.
    expr = mergedJsonNoPrivate ? privateOnly;
    expected = false;
  };

  testJsonHasNoOverlayKey = {
    # `share` is set only by tier 4 (private overlay file).
    expr = mergedJsonNoPrivate ? share;
    expected = false;
  };

  testExplicitNullPathsBehaveLikeOmitted = {
    # Passing privateOpencodeDir=null and privateConfigFile=null
    # explicitly must produce the same result as omitting them.
    expr = mergedJsonNoPrivate == mergedJsonNullPaths;
    expected = true;
  };

  testAgentsMdContainsOnlyPublic = {
    # No private rules, no imports — the AGENTS.md content should
    # include public rule fragments and nothing else.
    expr =
      lib.hasInfix "public-rule-10" agentsNoPrivate && lib.hasInfix "public-rule-20" agentsNoPrivate;
    expected = true;
  };

  testAgentsMdHasNoPrivateContent = {
    expr = lib.hasInfix "private-rule-" agentsNoPrivate;
    expected = false;
  };
}
