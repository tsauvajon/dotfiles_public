# Fallback macOS LaunchAgents loader for hand-authored XML plists.
#
# Prefer Home Manager's typed `launchd.agents.<name>` for new agents
# (see `home/launchd-goto.nix` for the canonical example) — that
# generates the plist from a typed schema and runs the
# bootstrap/bootout lifecycle automatically.
#
# This module exists for cases where you already have a hand-written
# XML plist and don't want to retype it. It scans two directories and
# symlinks every `.plist` it finds into `~/Library/LaunchAgents/`. It
# does NOT run `launchctl bootstrap`/`bootout`; you have to do that
# manually after adding or removing entries.
#
# Sources, in scan order:
#   1. Public:  <dotfiles>/config/plist/*.plist
#   2. Private: <inputs.private>/plist/*.plist
# Private wins on filename collision.
#
# Both directories are typically empty today; the typed
# `launchd.agents.dev.goto.api` lives in `home/launchd-goto.nix`.
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

  mkEntry =
    dir: name:
    lib.nameValuePair "Library/LaunchAgents/${name}" {
      source = "${toString dir}/${name}";
    };

  publicEntries = lib.listToAttrs (map (mkEntry publicDir) (plistsIn publicDir));
  privateEntries = lib.listToAttrs (map (mkEntry privateDir) (plistsIn privateDir));
in
lib.mkIf pkgs.stdenv.isDarwin {
  home.file = publicEntries // privateEntries;
}
