# Cargo config: base + platform overlay (config/cargo/cargo.*.toml) +
# private overlays (~/.config/dotfiles/cargo.*.toml), text-concatenated.
{
  pkgs,
  lib,
  inputs,
  ...
}:

let
  concatTomlFiles = import ../lib/concat-toml-files.nix { inherit pkgs lib; };

  privateDir = inputs.private;
  privateDirExists = builtins.pathExists privateDir;
  privateEntries = if privateDirExists then builtins.readDir privateDir else {};
  hasPrivateCargo = privateDirExists && (builtins.any (name: 
    let type = privateEntries.${name}; in
    (type == "regular" || type == "symlink") &&
    lib.hasPrefix "cargo." name && 
    lib.hasSuffix ".toml" name
  ) (builtins.attrNames privateEntries));

  cargoConfig = concatTomlFiles {
    name = "cargo-config.toml";
    base = ../../config/cargo/cargo-config.toml;
    fragmentDirs = lib.optionals pkgs.stdenv.isDarwin [ ../../config/cargo ] ++ lib.optionals hasPrivateCargo [ privateDir ];
    prefix = "cargo.";
  };
in
{
  home.file.".cargo/config.toml".source = cargoConfig;
}
