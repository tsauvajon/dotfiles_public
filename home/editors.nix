# Editors and AI coding tools.
#
# - `vscodium` is the FOSS VS Code build, Nix-managed here. The
#   proprietary Microsoft VS Code coexists but is Jamf-managed
#   (root-owned in /Applications) — not Brew, not Nix. See
#   `config/Brewfile` for why it must not be re-added there.
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
