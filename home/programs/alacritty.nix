# Alacritty config: base + private overlays
# (~/.config/dotfiles/alacritty.*.toml), plus alacritty-theme from
# nixpkgs symlinked so `import = [ "~/.config/alacritty/themes/<name>.toml" ]`
# directives in the user's config resolve. Phase 8 retired the
# alacritty-theme git submodule that used to live at
# `config/alacritty/themes/`.
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
    # pkgs.alacritty-theme has the full theme set under share/alacritty-theme/.
    # We mount that subdirectory directly so `~/.config/alacritty/themes/<name>.toml`
    # resolves the way the existing import paths expect.
    "alacritty/themes".source = "${pkgs.alacritty-theme}/share/alacritty-theme";
  };
}
