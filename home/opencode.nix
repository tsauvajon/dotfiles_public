# OpenCode public/private overlay merges.
#
# Replaces the Rust merge logic from src/merge.rs:
#
# - `commands`, `skills`, `agents`, `plugins`: per-tree directory merge,
#   private wins on collision. Built by `lib/merge-dirs.nix`.
# - `AGENTS.md`: concatenation of an optional public base plus private
#   rules overlays, sorted by filename. Built by `lib/concat-files.nix`.
#   `__DOTFILES_PATH__` is substituted to the actual repo path.
# - `opencode.json` and `package.json`: deep JSON merge, private wins.
#   Built by `lib/deep-merge-json.nix`.
#
# Rules mode (`merged` / `private_only` / `disabled`) is exposed as a
# module option so the user's host config can override the default.
{
  pkgs,
  lib,
  config,
  inputs,
  dotfilesRoot,
  ...
}:

let
  cfg = config.programs.opencode;

  inherit (import ./lib/deep-merge-json.nix { inherit lib; }) deepMergeAll;
  mergeDirs = import ./lib/merge-dirs.nix { inherit pkgs lib; };
  concatFiles = import ./lib/concat-files.nix { inherit lib; };

  publicRoot = ../config/opencode;
  privatePaths = inputs.private.opencode;

  # Collect `opencode.*.json` JSON fragments in `dir`, sorted by
  # filename bytes (LC_ALL=C). Excludes the bare `opencode.json` so
  # the base/overlay are handled separately.
  jsonFragmentsIn =
    dir:
    if !builtins.pathExists dir then
      [ ]
    else
      let
        entries = builtins.readDir dir;
        accepted = lib.filterAttrs (
          name: type:
          (type == "regular" || type == "symlink")
          && lib.hasPrefix "opencode." name
          && lib.hasSuffix ".json" name
          && name != "opencode.json"
        ) entries;
        names = lib.sort (a: b: a < b) (builtins.attrNames accepted);
      in
      map (name: dir + "/${name}") names;

  # Pretty-print a JSON-shaped attrset to a file (sorted keys, 2-space
  # indent — jq's default). Matches serde_json structurally.
  prettyJson =
    name: value:
    pkgs.runCommand name {
      jsonContent = builtins.toJSON value;
      nativeBuildInputs = [ pkgs.jq ];
    } ''
      echo "$jsonContent" | jq . > $out
    '';

  # Read a JSON file if it exists, otherwise return an empty attrset.
  readJsonOr =
    path: default:
    if builtins.pathExists path then builtins.fromJSON (builtins.readFile path) else default;

  # Build commands / skills / agents / plugins merged dirs. The private
  # flake exposes paths by name; the public root mirrors the same
  # subdirectory layout under config/opencode/.
  mkMergedDir =
    {
      name,
      privatePath,
    }:
    mergeDirs {
      name = "opencode-${name}";
      sources = [
        (publicRoot + "/${name}")
        privatePath
      ];
    };

  mergedCommands = mkMergedDir {
    name = "commands";
    privatePath = privatePaths.commandsDir;
  };
  mergedSkills = mkMergedDir {
    name = "skills";
    privatePath = privatePaths.skillsDir;
  };
  mergedAgents = mkMergedDir {
    name = "agents";
    privatePath = privatePaths.agentsDir;
  };
  mergedPlugins = mkMergedDir {
    name = "plugins";
    privatePath = privatePaths.pluginsDir;
  };

  # AGENTS.md: depending on rulesMode, optionally include the public
  # base, then append private rules overlays. `__DOTFILES_PATH__` gets
  # substituted with the live dotfiles repo path.
  agentsBase = if cfg.rulesMode == "merged" then publicRoot + "/AGENTS.md" else null;
  agentsContent = concatFiles {
    base = agentsBase;
    fragmentDirs = [ privatePaths.rulesDir ];
    substitutions = {
      "__DOTFILES_PATH__" = dotfilesRoot;
    };
  };

  # opencode.json: 4-tier deep merge matching merge_opencode_json_to in
  # the Rust tool. Each tier wins over the previous on key collision.
  #
  #   1. public base       config/opencode/opencode.json
  #   2. repo fragments    config/opencode/opencode.*.json    (sorted)
  #   3. private fragments ~/.config/dotfiles/opencode/opencode.*.json
  #   4. private overlay   ~/.config/dotfiles/opencode/opencode.json
  publicJson = readJsonOr (publicRoot + "/opencode.json") { };
  repoJsonFragments = map (p: builtins.fromJSON (builtins.readFile p)) (
    jsonFragmentsIn publicRoot
  );
  # The private flake exposes the directory containing the JSON
  # fragments. `dirOf privatePaths.configFile` gives us that dir
  # without us having to expose another path.
  privateOpencodeDir = dirOf privatePaths.configFile;
  privateJsonFragments = map (p: builtins.fromJSON (builtins.readFile p)) (
    jsonFragmentsIn privateOpencodeDir
  );
  privateJson = readJsonOr privatePaths.configFile { };
  mergedJson = deepMergeAll (
    [ publicJson ] ++ repoJsonFragments ++ privateJsonFragments ++ [ privateJson ]
  );

  publicPackage = readJsonOr (publicRoot + "/package.json") { };
  privatePackage = readJsonOr privatePaths.packageFile { };
  mergedPackage = deepMergeAll [
    publicPackage
    privatePackage
  ];
  hasAnyPackage = publicPackage != { } || privatePackage != { };
in
{
  options.programs.opencode = {
    rulesMode = lib.mkOption {
      type = lib.types.enum [
        "merged"
        "private_only"
        "disabled"
      ];
      default = "merged";
      description = ''
        How to build ~/.config/opencode/AGENTS.md.
        - merged: public AGENTS + private rules overlays.
        - private_only: only private rules overlays.
        - disabled: do not manage AGENTS.md.
      '';
    };
  };

  config = {
    xdg.configFile = lib.mkMerge [
      {
        "opencode/commands".source = mergedCommands;
        "opencode/skills".source = mergedSkills;
        "opencode/agents".source = mergedAgents;
        "opencode/plugins".source = mergedPlugins;
        "opencode/opencode.json".source = prettyJson "opencode.json" mergedJson;
      }
      (lib.mkIf (cfg.rulesMode != "disabled") {
        "opencode/AGENTS.md".text = agentsContent;
      })
      (lib.mkIf hasAnyPackage {
        "opencode/package.json".source = prettyJson "opencode-package.json" mergedPackage;
      })
    ];
  };
}
