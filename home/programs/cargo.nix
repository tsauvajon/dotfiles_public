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

  # `concatTomlFiles` already guards each `fragmentDir` with
  # `pathExists`, so we can pass `inputs.private` unconditionally —
  # matches the pattern used in aerospace.nix and alacritty.nix.
  cargoConfig = concatTomlFiles {
    name = "cargo-config.toml";
    base = ../../config/cargo/cargo-config.toml;
    fragmentDirs =
      lib.optionals pkgs.stdenv.isDarwin [ ../../config/cargo ]
      ++ [ inputs.private ];
    prefix = "cargo.";
  };
in
{
  home.file.".cargo/config.toml".source = cargoConfig;
}
