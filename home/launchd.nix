# macOS LaunchAgents (~/Library/LaunchAgents/*.plist).
#
# The plists themselves are written by hand — HM's
# `launchd.user.agents` requires the typed schema (Label,
# ProgramArguments, ...), but we already have user-authored XML
# under ~/.config/dotfiles/plist/. So we just symlink them. HM
# does not run `launchctl unload` here (use `launchctl bootout`
# manually if you remove an entry).
#
# Sources, in scan order:
#   1. Public:  <dotfiles>/config/plist/*.plist
#   2. Private: <inputs.private>/plist/*.plist
# Private wins on filename collision.
{
  pkgs,
  lib,
  inputs,
  ...
}:

let
  publicDir = ../config/plist;
  privateDir = inputs.private + "/plist";

  plistsIn =
    dir:
    if !builtins.pathExists dir then
      [ ]
    else
      let
        entries = builtins.readDir dir;
        accepted = lib.filterAttrs (
          name: type: (type == "regular" || type == "symlink") && lib.hasSuffix ".plist" name
        ) entries;
      in
      builtins.attrNames accepted;

  mkEntry = dir: name: lib.nameValuePair "Library/LaunchAgents/${name}" {
    source = "${toString dir}/${name}";
  };

  publicEntries = lib.listToAttrs (map (mkEntry publicDir) (plistsIn publicDir));
  privateEntries = lib.listToAttrs (map (mkEntry privateDir) (plistsIn privateDir));
in
lib.mkIf pkgs.stdenv.isDarwin {
  home.file = publicEntries // privateEntries;
}
