# Tests `mkMergedPackage`: the @opencode-ai/plugin version is injected
# by the caller (`home/opencode.nix` passes `pkgs.opencode.version`),
# the public manifest contributes every other dependency, and the
# private overlay may deliberately override the injected pin.
#
# The guardrail mirrors `public-base-guardrail.nix`: a public manifest
# that pins @opencode-ai/plugin must abort the merge via assertMsg,
# because the injected version would silently win over the committed
# pin. `builtins.tryEval` + `deepSeq` turn that assert into a testable
# `success = false`.
{ lib }:

let
  inherit (import ../lib/opencode-merge.nix { inherit lib; }) mkMergedPackage;

  injected = mkMergedPackage {
    publicRoot = ./fixtures-package/public;
    pluginVersion = "9.8.7";
  };

  withPrivate = mkMergedPackage {
    publicRoot = ./fixtures-package/public;
    privatePackageFile = ./fixtures-package/private/package.json;
    pluginVersion = "9.8.7";
  };

  withoutDependenciesKey = mkMergedPackage {
    publicRoot = ./fixtures-package/public-without-dependencies;
    pluginVersion = "9.8.7";
  };

  missingPublicPackage = mkMergedPackage {
    publicRoot = ./fixtures-package/public-missing-package;
    pluginVersion = "9.8.7";
  };

  # Should fail: public-with-pin/package.json pins @opencode-ai/plugin.
  badResult = builtins.tryEval (
    builtins.deepSeq (mkMergedPackage {
      publicRoot = ./fixtures-package/public-with-pin;
      pluginVersion = "9.8.7";
    }) "ok"
  );
in
{
  testPluginVersionInjected = {
    expr = injected.dependencies."@opencode-ai/plugin";
    expected = "9.8.7";
  };

  testPublicDependencyPreserved = {
    expr = injected.dependencies."@ai-sdk/openai-compatible";
    expected = "9.9.9";
  };

  testPrivateOverlayOverridesInjectedPin = {
    expr = withPrivate.dependencies."@opencode-ai/plugin";
    expected = "0.0.0-private-skew";
  };

  testPrivateOverlayAddsDependency = {
    expr = withPrivate.dependencies."extra-private-dep";
    expected = "1.0.0";
  };

  testPublicManifestWithoutDependenciesStillGetsInjectedPlugin = {
    expr = withoutDependenciesKey.dependencies."@opencode-ai/plugin";
    expected = "9.8.7";
  };

  testPublicManifestWithoutDependenciesPreservesOtherKeys = {
    expr = withoutDependenciesKey.name;
    expected = "opencode-no-deps-fixture";
  };

  testMissingPublicPackageStillGetsInjectedPlugin = {
    expr = missingPublicPackage.dependencies."@opencode-ai/plugin";
    expected = "9.8.7";
  };

  testGuardrailFiresWhenPublicPinsPlugin = {
    expr = badResult.success;
    expected = false;
  };

  testRepoPublicManifestDoesNotPinPlugin = {
    # Guard the real committed manifest, not just fixtures: the public
    # package.json must rely on the injected version.
    expr = lib.attrByPath [ "dependencies" "@opencode-ai/plugin" ] null (
      builtins.fromJSON (builtins.readFile ../../config/opencode/package.json)
    );
    expected = null;
  };
}
