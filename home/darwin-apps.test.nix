{
  homeManagerLib,
  lib,
  supportedPkgs,
  unsupportedPkgs,
}:

let
  source = builtins.readFile ./darwin-apps.nix;
  unsupportedWarning = "programs.apiForCursor.enable is true, but API for Cursor is supported only on aarch64-darwin; no package or app alias will be installed.";
  evalUnsupported =
    enable:
    (homeManagerLib.homeManagerConfiguration {
      pkgs = unsupportedPkgs;
      extraSpecialArgs.inputs = { };
      modules = [
        ./darwin-apps.nix
        ./personal.nix
        {
          home.homeDirectory = "/home/test";
          home.stateVersion = "25.05";
          home.username = "test";
          programs.apiForCursor.enable = enable;
        }
      ];
    }).config;
  evalSupported =
    enable:
    (homeManagerLib.homeManagerConfiguration {
      pkgs = supportedPkgs;
      extraSpecialArgs.inputs = { };
      modules = [
        ./darwin-apps.nix
        ./personal.nix
        {
          home.homeDirectory = "/Users/test";
          home.stateVersion = "25.05";
          home.username = "test";
          programs.apiForCursor.enable = enable;
        }
      ];
    }).config;
  hasApiForCursorPackage =
    config: builtins.any (pkg: (pkg.pname or null) == "api-for-cursor") config.home.packages;
  supportedActivation = enable: (evalSupported enable).home.activation.linkDarwinAppAliases.data;
in
{
  testApiForCursorIsDisabledByDefault = {
    expr = lib.hasInfix ''options.programs.apiForCursor.enable = lib.mkEnableOption "API for Cursor";'' source;
    expected = true;
  };

  testApiForCursorPackageAndLauncherAreAppleSiliconGated = {
    expr =
      (lib.hasInfix ''apiForCursorSupported = pkgs.stdenv.hostPlatform.system == "aarch64-darwin";'' source)
      && (lib.hasInfix "apiForCursorLauncher = pkgs.stdenv.mkDerivation" source)
      && (lib.hasInfix "ai.standardagents.cursorapi.launcher" source)
      && (lib.hasInfix ''printf 'APPL????' > "$app/Contents/PkgInfo"'' source)
      && (lib.hasInfix ''args[0] = "/usr/bin/open";'' source)
      && (lib.hasInfix ''args[1] = "''${pkgs.api-for-cursor}/Applications/API for Cursor.app";'' source)
      && (lib.hasInfix "link_root_app_launcher 'API for Cursor.app' " (supportedActivation true))
      && !(lib.hasInfix "link_app_alias 'API for Cursor.app' " (supportedActivation true))
      && !(lib.hasInfix "link_root_app_launcher 'API for Cursor.app' " (supportedActivation false));
    expected = true;
  };

  testDarwinAppsStillUseFinderAliases = {
    expr = lib.all (name: lib.hasInfix "link_app_alias ${name}.app" (supportedActivation false)) [
      "AeroSpace"
      "Alacritty"
      "Kitty"
      "Obsidian"
      "KeePassXC"
    ];
    expected = true;
  };

  testApiForCursorWarnsWhenEnabledOnUnsupportedHost = {
    expr = lib.elem unsupportedWarning (evalUnsupported true).warnings;
    expected = true;
  };

  testApiForCursorDoesNotWarnWhenDisabledOnUnsupportedHost = {
    expr = lib.elem unsupportedWarning (evalUnsupported false).warnings;
    expected = false;
  };

  testApiForCursorInstallsPackageWhenEnabledOnAppleSilicon = {
    expr = hasApiForCursorPackage (evalSupported true);
    expected = true;
  };

  testApiForCursorDoesNotInstallPackageWhenDisabledOnAppleSilicon = {
    expr = hasApiForCursorPackage (evalSupported false);
    expected = false;
  };

}
