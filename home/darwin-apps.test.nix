{ lib }:

let
  source = builtins.readFile ./darwin-apps.nix;
in
{
  testDarwinAppsUseFinderAliases = {
    expr = lib.all (name: lib.hasInfix ''name = "${name}.app";'' source) [
      "AeroSpace"
      "Alacritty"
      "Kitty"
      "Obsidian"
      "KeePassXC"
    ];
    expected = true;
  };
}
