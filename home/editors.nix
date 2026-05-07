# Editors and AI coding tools.
#
# - `obsidian` is Nix-only here; the matching Brew cask was retired.
# - `vscodium` is the FOSS VS Code build, Nix-managed here. The
#   proprietary Microsoft VS Code is intentionally kept on Brew via
#   `config/Brewfile`, so both editors coexist (`codium` from Nix,
#   `code` from Brew). Drop one of them if you stop using it.
# - `opencode` is skipped on x86_64-darwin (no upstream build).
{ pkgs, lib, ... }:

{
  home.packages =
    with pkgs;
    [
      neovim
      obsidian
      vim
      vscodium
    ]
    ++ lib.optional (stdenv.hostPlatform.system != "x86_64-darwin") opencode;
}
