# Editors and AI coding tools.
#
# - `vscodium` is the FOSS VS Code build, Nix-managed here. The
#   proprietary Microsoft VS Code is intentionally kept on Brew via
#   `config/Brewfile`, so both editors coexist (`codium` from Nix,
#   `code` from Brew).
# - `opencode`: nixpkgs has no x86_64-darwin build.
{ pkgs, inputs, ... }:
{
  home.packages =
    with pkgs;
    [
      neovim
      obsidian
      inputs.opencode.packages.${pkgs.stdenv.system}.opencode
      vim
      vscodium
    ];
}
