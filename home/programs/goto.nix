# Wire the upstream goto Home Manager module into this flake.
#
# Identity (apiUrl, bookmarksFile) flows from the private flake which
# reads them from ~/.config/dotfiles/config.toml and the optional
# ~/.config/dotfiles/goto/database.yml.
{ inputs, lib, ... }:

let
  privateGoto = inputs.private.goto;
  hasGoto = lib.isString privateGoto.apiUrl && privateGoto.apiUrl != "";
in
{
  imports = [ inputs.goto.homeManagerModules.default ];

  programs.gotoLinks = lib.mkIf hasGoto {
    enable = true;
    apiUrl = privateGoto.apiUrl;
    bookmarksFile = privateGoto.bookmarksFile;
  };
}
