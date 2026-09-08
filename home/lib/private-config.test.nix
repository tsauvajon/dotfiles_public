{ lib }:

let
  privateConfigLib = import ./private-config.nix { inherit lib; };
  minimal = privateConfigLib.normalize {
    git = {
      name = "Test User";
      email = "test@example.com";
      signingKey = "/tmp/test.pub";
    };
  };
  explicitNulls = privateConfigLib.normalize {
    git = null;
    goto = null;
    personal = {
      enable = null;
      signal = null;
    };
    opencode = null;
    homeModules = null;
  };
in
{
  testMinimalGitOnlyPrivateFlakeGetsOptionalSections = {
    expr = {
      inherit (minimal)
        goto
        homeModules
        opencode
        personal
        ;
    };
    expected = {
      goto = { };
      homeModules = [ ];
      opencode = { };
      personal = lib.genAttrs [
        "signal"
        "syncthing"
        "chromium"
        "naps2"
        "tailscale"
        "plezy"
        "immich"
        "printer-exporter"
        "cups-exporter"
        "brother-maintenance-exporter"
        "opencode-exporter"
        "opencode-ingress"
        "unifi-exporter"
      ] (_: { });
    };
  };

  testNullSectionsNormalizeAtKnownBoundaries = {
    expr = {
      inherit (explicitNulls)
        git
        goto
        homeModules
        opencode
        ;
      personalSignal = explicitNulls.personal.signal;
    };
    expected = {
      git = { };
      goto = { };
      homeModules = [ ];
      opencode = { };
      personalSignal = { };
    };
  };

  testLeafNullIsPreserved = {
    expr = explicitNulls.personal.enable;
    expected = null;
  };

  testOpencodePathNullRemainsAnExplicitDisable = {
    expr = (privateConfigLib.normalize { opencode.commandsDir = null; }).opencode.commandsDir;
    expected = null;
  };

  testOpencodeNullListSettingUsesEmptyDefault = {
    expr =
      privateConfigLib.valueOr (privateConfigLib.normalize { opencode.imports = null; }).opencode
        "imports"
        [ ];
    expected = [ ];
  };

  testValueOrTreatsMissingAndNullAsDefault = {
    expr = [
      (privateConfigLib.valueOr { } "enable" false)
      (privateConfigLib.valueOr { enable = null; } "enable" false)
      (privateConfigLib.valueOr { enable = true; } "enable" false)
    ];
    expected = [
      false
      false
      true
    ];
  };

  testUnknownPersonalFieldsArePreserved = {
    expr = (privateConfigLib.normalize { personal.futureSetting = "kept"; }).personal.futureSetting;
    expected = "kept";
  };

  testInvalidSectionFailsClearlyAtBoundary = {
    expr =
      (builtins.tryEval (builtins.deepSeq (privateConfigLib.normalize { personal = true; }) true))
      .success;
    expected = false;
  };

  testInvalidHomeModulesFailsClearlyAtBoundary = {
    expr =
      (builtins.tryEval (builtins.deepSeq (privateConfigLib.normalize { homeModules = { }; }) true))
      .success;
    expected = false;
  };
}
