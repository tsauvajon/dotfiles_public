# Editors and AI coding tools.
#
# - `vscodium` is the FOSS VS Code build, Nix-managed here. The
#   proprietary Microsoft VS Code is intentionally kept on Brew via
#   `config/Brewfile`, so both editors coexist (`codium` from Nix,
#   `code` from Brew).
{ pkgs, ... }:
{
  home.packages =
    with pkgs;
    [
      neovim
      obsidian
      opencode
      vim
      vscodium
    ];
}
