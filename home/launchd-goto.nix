# Typed launchd agent for the local goto-api server.
#
# Replaces the hand-written plist that used to live at
# `~/.config/dotfiles/plist/dev.goto.api.plist` and was symlinked into
# `~/Library/LaunchAgents/` via `home/launchd.nix`.
#
# Home Manager's `launchd.agents.<name>` writes a generated plist to
# `~/Library/LaunchAgents/<label>.plist` and manages the launchctl
# bootstrap/bootout lifecycle on activation. No sudo required.
#
# The agent is gated on the private flake providing both an `apiUrl`
# (so we know the user wants goto running) and a `bookmarksFile`
# (the database the api reads from).
{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  privateGoto = inputs.private.goto or { };
  apiUrl = privateGoto.apiUrl or null;
  bookmarksFile = privateGoto.bookmarksFile or null;
  hasBookmarksFile = bookmarksFile != null && toString bookmarksFile != "";
  hasGoto = lib.isString apiUrl && apiUrl != "" && hasBookmarksFile;

  privateStoreRoot = toString inputs.private;
  privateWritableRoot = "${config.home.homeDirectory}/.config/dotfiles";
  rawBookmarksFile = toString bookmarksFile;
  bookmarksFileArg =
    if lib.hasPrefix "${privateStoreRoot}/" rawBookmarksFile then
      "${privateWritableRoot}/${lib.removePrefix "${privateStoreRoot}/" rawBookmarksFile}"
    else if lib.hasPrefix "~/" rawBookmarksFile then
      "${config.home.homeDirectory}/${lib.removePrefix "~/" rawBookmarksFile}"
    else
      rawBookmarksFile;
in
lib.mkIf (pkgs.stdenv.isDarwin && hasGoto) {
  launchd.agents."dev.goto.api" = {
    enable = true;
    config = {
      Label = "dev.goto.api";
      ProgramArguments = [
        "${config.home.profileDirectory}/bin/goto-api"
        "--addr"
        "127.0.0.1:50002"
        # Path literals from the private flake resolve to the Nix store.
        # goto-api opens the db read+write, so map private-flake paths
        # back to their writable source under ~/.config/dotfiles.
        "--database"
        bookmarksFileArg
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/goto.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/goto-error.log";
    };
  };
}
