# Wire the upstream goto Home Manager module into this flake.
#
# Identity (apiUrl, bookmarksFile) comes from the private flake at
# ~/.config/dotfiles/flake.nix under the `goto` attribute. Both
# fields are optional — when `apiUrl` is null/empty, programs.goto
# stays disabled and no goto config is generated.
{ inputs, lib, ... }:

let
  privateGoto = inputs.private.goto or { };
  apiUrl = privateGoto.apiUrl or null;
  bookmarksFile = privateGoto.bookmarksFile or null;
  hasGoto = lib.isString apiUrl && apiUrl != "";
in
{
  imports = [ inputs.goto.homeManagerModules.default ];

  programs.gotoLinks = lib.mkIf hasGoto {
    enable = true;
    inherit apiUrl bookmarksFile;
  };
}
