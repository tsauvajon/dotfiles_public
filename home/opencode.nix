# OpenCode public/private overlay merges.
#
# Replaces the Rust merge logic from src/merge.rs:
#
# - `commands`, `skills`, `agents`, `plugins`: per-tree directory merge,
#   private wins on collision. Built by `lib/merge-dirs.nix`.
# - `AGENTS.md`: cross-source fragment merge. Public rules in
#   `config/opencode/rules/` and private rules in
#   `~/.config/dotfiles/opencode/rules/` are collected together,
#   filename collisions resolve in favor of the private overlay, and
#   the surviving fragments are sorted by filename in byte order
#   (LC_ALL=C). Built by `lib/concat-files.nix`.
# - `opencode.*.json` partials and `package.json`: deep JSON merge,
#   private wins. The public side is fragment-only — there is no
#   `config/opencode/opencode.json`; every section lives in its own
#   `opencode.<scope>.json` file (meta, watcher, permission.{bash,fs,web},
#   experimental.quotaToast). Built by `lib/deep-merge-json.nix`.
#
# Rules mode (`merged` / `private_only` / `disabled`) is exposed as a
# module option so the user's host config can override the default.
{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

let
  cfg = config.programs.opencode;

  inherit (import ./lib/deep-merge-json.nix { inherit lib; }) deepMergeAll;
  mergeDirs = import ./lib/merge-dirs.nix { inherit pkgs lib; };
  concatFiles = import ./lib/concat-files.nix { inherit lib; };

  publicRoot = ../config/opencode;
  privatePaths = inputs.private.opencode;

  # Guardrail: the public side is fragment-only (`opencode.<scope>.json`).
  # A bare `config/opencode/opencode.json` would be silently ignored by
  # the fragment filter (`name != "opencode.json"`), which is a real
  # footgun if someone restores it from a backup or copies it back by
  # mistake. Force the build to fail early with a clear message instead.
  publicBaseExists = builtins.pathExists (publicRoot + "/opencode.json");

  # External imports staged by setup.sh into
  # ~/.config/dotfiles/opencode-imports/<name>/. Each entry is a Nix
  # path with the standard opencode/ layout (commands/, skills/,
  # agents/, plugins/, rules/, opencode.*.json). Treated as additional
  # sources sandwiched between public and private so private always
  # wins.
  importsDirs = privatePaths.importsDirs or [ ];

  # Helper: subdir of an import dir if it exists, else null.
  importSubdir =
    sub: dir:
    let
      p = dir + "/${sub}";
    in
    if builtins.pathExists p then p else null;

  importDirsFor =
    sub:
    lib.filter (x: x != null) (
      map (importSubdir sub) importsDirs
    );

  importCommandsDirs = importDirsFor "commands";
  importSkillsDirs = importDirsFor "skills";
  importAgentsDirs = importDirsFor "agents";
  importPluginsDirs = importDirsFor "plugins";
  importRulesDirs = importDirsFor "rules";

  # Collect `opencode.*.json` JSON fragments in `dir`, sorted by
  # filename bytes (LC_ALL=C). Excludes the bare `opencode.json` so
  # the private overlay file (tier 4) is handled separately; the public
  # side has no `opencode.json` so this filter is a no-op there.
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
  # subdirectory layout under config/opencode/. Imports are sandwiched
  # between public and private so private always wins on collision.
  mkMergedDir =
    {
      name,
      privatePath,
      importDirs ? [ ],
    }:
    mergeDirs {
      name = "opencode-${name}";
      sources =
        [ (publicRoot + "/${name}") ]
        ++ importDirs
        ++ [ privatePath ];
    };

  mergedCommands = mkMergedDir {
    name = "commands";
    privatePath = privatePaths.commandsDir;
    importDirs = importCommandsDirs;
  };
  mergedSkills = mkMergedDir {
    name = "skills";
    privatePath = privatePaths.skillsDir;
    importDirs = importSkillsDirs;
  };
  mergedAgents = mkMergedDir {
    name = "agents";
    privatePath = privatePaths.agentsDir;
    importDirs = importAgentsDirs;
  };
  mergedPlugins = mkMergedDir {
    name = "plugins";
    privatePath = privatePaths.pluginsDir;
    importDirs = importPluginsDirs;
  };

  # AGENTS.md: collect rule fragments from public, imports, and/or
  # private directories depending on rulesMode, then concat-sort by
  # filename across all sources. Private last so it wins on collision;
  # imports sit between public and private with the same precedence
  # ordering used for commands/skills/agents/plugins.
  agentsFragmentDirs =
    if cfg.rulesMode == "merged" then
      [ (publicRoot + "/rules") ] ++ importRulesDirs ++ [ privatePaths.rulesDir ]
    else if cfg.rulesMode == "private_only" then
      importRulesDirs ++ [ privatePaths.rulesDir ]
    else
      [ ];
  agentsContent = concatFiles {
    fragmentDirs = agentsFragmentDirs;
  };

  # opencode.json: 4-tier deep merge. Each tier wins over the previous
  # on key collision (private always last so it overrides everything).
  # The merged result is written to ~/.config/opencode/opencode.json;
  # there is intentionally no public base file — the public side is
  # fragment-only so every section has a self-documenting filename
  # (opencode.meta.json, opencode.permission.bash.json, etc.).
  #
  #   1. repo fragments    config/opencode/opencode.*.json     (sorted)
  #   2. import fragments  opencode-imports/<name>/opencode.*.json
  #                        (sorted within each import; imports applied
  #                        in flake-declared order)
  #   3. private fragments ~/.config/dotfiles/opencode/opencode.*.json
  #   4. private overlay   ~/.config/dotfiles/opencode/opencode.json
  repoJsonFragments = map (p: builtins.fromJSON (builtins.readFile p)) (
    jsonFragmentsIn publicRoot
  );
  importJsonFragments = lib.concatMap (
    d: map (p: builtins.fromJSON (builtins.readFile p)) (jsonFragmentsIn d)
  ) importsDirs;
  # JSON fragments live next to the private overlay's `opencode/` dir.
  # We derive that explicitly from `inputs.private.outPath` so the
  # discovery root stays stable even if `configFile` is ever pointed
  # somewhere unusual by a downstream private flake.
  privateOpencodeDir = inputs.private.outPath + "/opencode";
  privateJsonFragments = map (p: builtins.fromJSON (builtins.readFile p)) (
    jsonFragmentsIn privateOpencodeDir
  );
  privateJson = readJsonOr privatePaths.configFile { };
  mergedJson =
    assert lib.assertMsg (!publicBaseExists) ''
      config/opencode/opencode.json must not exist.
      The public side is fragment-only — split content into one of the
      `opencode.<scope>.json` partials (meta, watcher, permission.bash,
      permission.fs, permission.web, experimental.quotaToast).
      See AGENTS.md > "opencode.json (4-tier deep merge)" for details.
    '';
    deepMergeAll (
      repoJsonFragments
      ++ importJsonFragments
      ++ privateJsonFragments
      ++ [ privateJson ]
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
        - merged: public + private rule fragments sorted together.
        - private_only: only private rule fragments.
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
        # tui.json is a separate OpenCode file (different $schema) — not
        # part of the opencode.json deep-merge. Symlinked verbatim from
        # the public source.
        "opencode/tui.json".source = publicRoot + "/tui.json";
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
