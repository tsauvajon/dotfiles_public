# Alacritty config: base + private overlays
# (~/.config/dotfiles/alacritty.*.toml), plus the themes submodule
# symlinked alongside so the `import = [ "themes/themes/omni.toml" ]`
# directive resolves.
{
  pkgs,
  lib,
  inputs,
  ...
}:

let
  concatTomlFiles = import ../lib/concat-toml-files.nix { inherit pkgs lib; };

  alacrittyConfig = concatTomlFiles {
    name = "alacritty.toml";
    base = ../../config/alacritty/alacritty.toml;
    fragmentDirs = [
      ../../config/alacritty
      inputs.private
    ];
    prefix = "alacritty.";
  };
in
{
  xdg.configFile = {
    "alacritty/alacritty.toml".source = alacrittyConfig;
    "alacritty/themes".source = ../../config/alacritty/themes;
  };
}
