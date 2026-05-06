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
  # Every field of `inputs.private.opencode` is optional. A user's
  # private flake.nix may omit the entire `opencode` attribute (the
  # placeholder does), in which case we fall back to an empty attrset
  # and every consumed path is null.
  privatePaths = inputs.private.opencode or { };

  # Guardrail: the public side is fragment-only (`opencode.<scope>.json`).
  # A bare `config/opencode/opencode.json` would be silently ignored by
  # the fragment filter (`name != "opencode.json"`), which is a real
  # footgun if someone restores it from a backup or copies it back by
  # mistake. Force the build to fail early with a clear message instead.
  publicBaseExists = builtins.pathExists (publicRoot + "/opencode.json");

  # External imports staged by setup.sh into
  # ~/.config/dotfiles/opencode-imports/<name>/. The private flake only
  # needs to declare `opencode.imports`; the HM build derives the staged
  # directories from each import name. `importsDirs` remains as a legacy
  # escape hatch for hand-written private flakes.
  declaredImports = privatePaths.imports or [ ];
  stagedImportsDirs = map (i: inputs.private.outPath + "/opencode-imports/${i.name}") declaredImports;
  importsDirs = stagedImportsDirs ++ (privatePaths.importsDirs or [ ]);

  # Each *Dir field is optional in the private flake. Null is filtered
  # out below before being passed to mergeDirs / concatFiles.
  privateCommandsDir = privatePaths.commandsDir or null;
  privateSkillsDir = privatePaths.skillsDir or null;
  privateAgentsDir = privatePaths.agentsDir or null;
  privatePluginsDir = privatePaths.pluginsDir or null;
  privateRulesDir = privatePaths.rulesDir or null;
  privateConfigFile = privatePaths.configFile or null;
  privatePackageFile = privatePaths.packageFile or null;

  # Helper: subdir of an import dir if it exists, else null.
  importSubdir =
    sub: dir:
    let
      p = dir + "/${sub}";
    in
    if builtins.pathExists p then p else null;

  importDirsFor = sub: lib.filter (x: x != null) (map (importSubdir sub) importsDirs);

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
        # `builtins.attrNames` already returns names in byte-sorted order.
        names = builtins.attrNames accepted;
      in
      map (name: dir + "/${name}") names;

  # Pretty-print a JSON-shaped attrset to a file (sorted keys, 2-space
  # indent — jq's default). Matches serde_json structurally.
  prettyJson =
    name: value:
    pkgs.runCommand name
      {
        jsonContent = builtins.toJSON value;
        nativeBuildInputs = [ pkgs.jq ];
      }
      ''
        echo "$jsonContent" | jq . > $out
      '';

  # Read a JSON file if it exists, otherwise return an empty attrset.
  # `null` short-circuits to the default so callers can pass an
  # optional path straight through.
  readJsonOr =
    path: default:
    if path == null || !builtins.pathExists path then
      default
    else
      builtins.fromJSON (builtins.readFile path);

  # Build commands / skills / agents / plugins merged dirs. The private
  # flake exposes paths by name; the public root mirrors the same
  # subdirectory layout under config/opencode/. Imports are sandwiched
  # between public and private so private always wins on collision.
  # `privatePath` is optional — null is filtered out before merging
  # so a private flake without the corresponding overlay still works.
  mkMergedDir =
    {
      name,
      privatePath,
      importDirs ? [ ],
    }:
    mergeDirs {
      name = "opencode-${name}";
      sources = [
        (publicRoot + "/${name}")
      ]
      ++ importDirs
      ++ lib.optional (privatePath != null) privatePath;
    };

  mergedCommands = mkMergedDir {
    name = "commands";
    privatePath = privateCommandsDir;
    importDirs = importCommandsDirs;
  };
  mergedSkills = mkMergedDir {
    name = "skills";
    privatePath = privateSkillsDir;
    importDirs = importSkillsDirs;
  };
  mergedAgents = mkMergedDir {
    name = "agents";
    privatePath = privateAgentsDir;
    importDirs = importAgentsDirs;
  };
  mergedPlugins = mkMergedDir {
    name = "plugins";
    privatePath = privatePluginsDir;
    importDirs = importPluginsDirs;
  };

  # AGENTS.md: collect rule fragments from public, imports, and/or
  # private directories depending on rulesMode, then concat-sort by
  # filename across all sources. Private last so it wins on collision;
  # imports sit between public and private with the same precedence
  # ordering used for commands/skills/agents/plugins. `privateRulesDir`
  # is optional; null is filtered out so a flake without rules still
  # produces a valid (public-only) AGENTS.md.
  privateRulesList = lib.optional (privateRulesDir != null) privateRulesDir;
  agentsFragmentDirs =
    if cfg.rulesMode == "merged" then
      [ (publicRoot + "/rules") ] ++ importRulesDirs ++ privateRulesList
    else if cfg.rulesMode == "private_only" then
      importRulesDirs ++ privateRulesList
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
  repoJsonFragments = map (p: builtins.fromJSON (builtins.readFile p)) (jsonFragmentsIn publicRoot);
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
  privateJson = readJsonOr privateConfigFile { };
  mergedJson =
    assert lib.assertMsg (!publicBaseExists) ''
      config/opencode/opencode.json must not exist.
      The public side is fragment-only — split content into one of the
      `opencode.<scope>.json` partials (meta, watcher, permission.bash,
      permission.fs, permission.web, experimental.quotaToast).
      See AGENTS.md > "opencode.json (4-tier deep merge)" for details.
    '';
    deepMergeAll (repoJsonFragments ++ importJsonFragments ++ privateJsonFragments ++ [ privateJson ]);

  publicPackage = readJsonOr (publicRoot + "/package.json") { };
  privatePackage = readJsonOr privatePackageFile { };
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

    # Auto-install plugin dependencies when the merged package.json
    # content changes. The merged file is a /nix/store symlink so we
    # hash it (not the symlink) and stash the hash under XDG_CACHE_HOME
    # to detect drift across HM generations.
    #
    # `bun install` writes node_modules/ and bun.lock into the symlink's
    # parent dir (~/.config/opencode/), which is HM-managed but not the
    # symlink target — that works fine. We invoke bun via its store path
    # because HM activation runs with a minimal PATH that does not yet
    # include the user profile's bin dir.
    home.activation = lib.mkIf hasAnyPackage {
      opencodeBunInstall = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        pkg="${config.xdg.configHome}/opencode/package.json"
        marker="${config.xdg.cacheHome}/dotfiles/opencode-package.sha256"
        ${pkgs.coreutils}/bin/mkdir -p "$(dirname "$marker")"
        if [ -f "$pkg" ]; then
          new_hash=$(${pkgs.coreutils}/bin/sha256sum "$pkg" | ${pkgs.coreutils}/bin/cut -d' ' -f1)
          old_hash=$(${pkgs.coreutils}/bin/cat "$marker" 2>/dev/null || true)
          if [ "$new_hash" != "$old_hash" ]; then
            echo "==> opencode/package.json changed; running bun install"
            ( cd "$(dirname "$pkg")" && ${pkgs.bun}/bin/bun install ) || true
            printf '%s\n' "$new_hash" > "$marker"
          fi
        fi
      '';
    };
  };
}
