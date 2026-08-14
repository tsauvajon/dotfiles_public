# AeroSpace window manager config: base + private overlays
# (~/.config/dotfiles/aerospace.*.toml). Macos-only.
{
  pkgs,
  lib,
  inputs,
  terminal,
  ...
}:

let
  concatTomlFiles = import ../lib/concat-toml-files.nix { inherit pkgs lib; };
  aerospaceSource = builtins.readFile ../../config/aerospace/aerospace.toml;
  aerospaceBaseDir = pkgs.writeTextDir "aerospace.toml" (
    assert lib.assertMsg (lib.hasInfix "__DEFAULT_TERMINAL_APP__" aerospaceSource)
      "config/aerospace/aerospace.toml is missing the default terminal app placeholder";
    lib.replaceStrings [ "__DEFAULT_TERMINAL_APP__" ] [ terminal.darwinAppName ] aerospaceSource
  );

  aerospaceConfig = concatTomlFiles {
    name = "aerospace.toml";
    base = "${aerospaceBaseDir}/aerospace.toml";
    fragmentDirs = [
      ../../config/aerospace
      inputs.private
    ];
    prefix = "aerospace.";
  };
in
lib.mkIf pkgs.stdenv.isDarwin {
  home.file.".aerospace.toml".source = aerospaceConfig;

  home.activation.reloadAerospace = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    ${pkgs.aerospace}/bin/aerospace reload-config
  '';
}
