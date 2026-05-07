# Tests `mkAgentsContent` behaviour across the three rulesMode values:
#   - "merged":       public + import + private rules, sorted by filename.
#   - "private_only": import + private rules only (public excluded).
#   - "disabled":     empty string (caller skips writing the file).
#
# Within "merged" mode, the byte-sorted filename order across all dirs
# is: 10-public.md, 15-import.md, 20-shared.md, 30-private.md.
# `20-shared.md` exists in both public and private; private wins.
{ lib }:

let
  inherit (import ../lib/opencode-merge.nix { inherit lib; }) mkAgentsContent;

  mkContent =
    rulesMode:
    mkAgentsContent {
      inherit rulesMode;
      publicRulesDir = ./fixtures/public/rules;
      importRulesDirs = [ ./fixtures/imports/sample/rules ];
      privateRulesDir = ./fixtures/private/rules;
    };

  mergedContent = mkContent "merged";
  privateOnlyContent = mkContent "private_only";
  disabledContent = mkContent "disabled";
in
{
  testMergedHasPublicRule = {
    expr = lib.hasInfix "public-rule-10" mergedContent;
    expected = true;
  };

  testMergedHasImportRule = {
    expr = lib.hasInfix "import-rule-15" mergedContent;
    expected = true;
  };

  testMergedSharedRulePrivateWins = {
    # 20-shared.md collides between public and private. Private's
    # content must appear in the merged output...
    expr = lib.hasInfix "private-rule-20-overrides-public" mergedContent;
    expected = true;
  };

  testMergedSharedRulePublicLost = {
    # ...and public's content for the same filename must NOT appear.
    expr = lib.hasInfix "public-rule-20" mergedContent;
    expected = false;
  };

  testMergedHasPrivateOnlyRule = {
    expr = lib.hasInfix "private-rule-30" mergedContent;
    expected = true;
  };

  testPrivateOnlyExcludesPublic = {
    # private_only mode must not include public/10-public.md.
    expr = lib.hasInfix "public-rule-10" privateOnlyContent;
    expected = false;
  };

  testPrivateOnlyIncludesImports = {
    # Imports are still included in private_only mode (alongside private).
    expr = lib.hasInfix "import-rule-15" privateOnlyContent;
    expected = true;
  };

  testPrivateOnlyIncludesPrivate = {
    expr = lib.hasInfix "private-rule-30" privateOnlyContent;
    expected = true;
  };

  testDisabledIsEmpty = {
    # `disabled` mode produces no fragment dirs, so the result is "".
    # The HM module wraps the file in `lib.mkIf rulesMode != "disabled"`,
    # so an empty string here means the file is never written.
    expr = disabledContent;
    expected = "";
  };
}
