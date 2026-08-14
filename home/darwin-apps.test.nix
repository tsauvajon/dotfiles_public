{ lib }:

let
  source = builtins.readFile ./darwin-apps.nix;
in
{
  testDarwinAppsUseFinderAliases = {
    expr = lib.all (name: lib.hasInfix ''name = "${name}.app";'' source) [
      "AeroSpace"
      "Obsidian"
      "KeePassXC"
    ];
    expected = true;
  };

  testDarwinAppsUseSelectedTerminalAlias = {
    expr =
      lib.hasInfix "name = terminal.darwinAppName;" source
      && lib.hasInfix (builtins.concatStringsSep "" [
        "target = \""
        "$"
        "{terminal.package}/Applications/"
        "$"
        "{terminal.darwinAppName}\";"
      ]) source;
    expected = true;
  };
}
