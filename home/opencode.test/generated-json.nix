# Tests compact serialization for the generated OpenCode JSON files.
{ lib }:

let
  inherit (import ../lib/opencode-merge.nix { inherit lib; })
    mkMergedOpencodeJson
    mkMergedPackage
    toCompactJson
    ;

  mergedOpencode = mkMergedOpencodeJson {
    publicRoot = ./fixtures/public;
    importsDirs = [ ./fixtures/imports/sample ];
    privateOpencodeDir = ./fixtures/private;
    privateConfigFile = ./fixtures/private/opencode.json;
  };

  mergedPackage = mkMergedPackage {
    publicRoot = ./fixtures-package/public;
    privatePackageFile = ./fixtures-package/private/package.json;
    pluginVersion = "9.8.7";
  };
in
{
  testGeneratedJsonIsCompact = {
    expr = toCompactJson {
      alpha = "value";
      nested = {
        enabled = true;
        items = [
          1
          "two"
        ];
      };
    };
    expected = ''{"alpha":"value","nested":{"enabled":true,"items":[1,"two"]}}'';
  };

  testCompactOpencodeJsonPreservesMergedSemantics = {
    expr = builtins.fromJSON (toCompactJson mergedOpencode);
    expected = mergedOpencode;
  };

  testCompactPackageJsonPreservesMergedSemantics = {
    expr = builtins.fromJSON (toCompactJson mergedPackage);
    expected = mergedPackage;
  };
}
