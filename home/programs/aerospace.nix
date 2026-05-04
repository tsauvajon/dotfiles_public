# AeroSpace window manager config: base + private overlays
# (~/.config/dotfiles/aerospace.*.toml). Macos-only.
{
  pkgs,
  lib,
  inputs,
  ...
}:

let
  concatTomlFiles = import ../lib/concat-toml-files.nix { inherit pkgs lib; };

  aerospaceConfig = concatTomlFiles {
    name = "aerospace.toml";
    base = ../../config/aerospace/aerospace.toml;
    fragmentDirs = [
      ../../config/aerospace
      inputs.private
    ];
    prefix = "aerospace.";
  };
in
lib.mkIf pkgs.stdenv.isDarwin {
  home.file.".aerospace.toml".source = aerospaceConfig;
}
