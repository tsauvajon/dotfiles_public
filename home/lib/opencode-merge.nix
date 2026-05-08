# Pure merge logic for OpenCode config.
#
# Extracted from `home/opencode.nix` so the multi-tier merge behaviour
# can be unit-tested without instantiating a full Home Manager module.
# `home/opencode.nix` consumes this file for the JSON and AGENTS.md
# computations; the directory merges (commands/skills/agents/plugins)
# stay in `home/opencode.nix` because they produce derivations and are
# already covered by the lib `merge-dirs.test.nix` integration test.
{ lib }:

let
  inherit (import ./deep-merge-json.nix { inherit lib; }) deepMergeAll;
  concatFiles = import ./concat-files.nix { inherit lib; };
  listFilesIn = import ./list-files-in.nix { inherit lib; };
  readJsonOr = import ./read-json-or.nix;

  # List `opencode.*.json` fragment files in `dir`, sorted by filename
  # bytes (LC_ALL=C). Excludes the bare `opencode.json` so the
  # private overlay file (tier 4) can be handled separately. Returns
  # an empty list if `dir` does not exist.
  jsonFragmentsIn =
    dir:
    map (name: dir + "/${name}") (listFilesIn {
      inherit dir;
      predicate =
        name: type:
        (type == "regular" || type == "symlink")
        && lib.hasPrefix "opencode." name
        && lib.hasSuffix ".json" name
        && name != "opencode.json";
    });

  # Compute the merged `opencode.json` value by combining the four
  # tiers in order, with later tiers winning on key collision:
  #
  #   1. repo fragments     publicRoot/opencode.*.json           (sorted)
  #   2. import fragments   importsDirs[*]/opencode.*.json
  #                         (sorted within each import; imports
  #                         applied in flake-declared order)
  #   3. private fragments  privateOpencodeDir/opencode.*.json   (sorted)
  #   4. private overlay    privateConfigFile (a single JSON file)
  #
  # The merge fails fast (via assertMsg) if `publicRoot` contains a
  # bare `opencode.json`, since that would be silently ignored by the
  # fragment filter and shadow the contract documented in AGENTS.md.
  mkMergedOpencodeJson =
    {
      publicRoot,
      importsDirs ? [ ],
      privateOpencodeDir ? null,
      privateConfigFile ? null,
    }:
    let
      publicBaseExists = builtins.pathExists (publicRoot + "/opencode.json");
      repoFragments = map (p: builtins.fromJSON (builtins.readFile p)) (jsonFragmentsIn publicRoot);
      importFragments = lib.concatMap (
        d: map (p: builtins.fromJSON (builtins.readFile p)) (jsonFragmentsIn d)
      ) importsDirs;
      privateFragments =
        if privateOpencodeDir == null then
          [ ]
        else
          map (p: builtins.fromJSON (builtins.readFile p)) (jsonFragmentsIn privateOpencodeDir);
      privateOverlay = readJsonOr privateConfigFile { };
    in
    assert lib.assertMsg (!publicBaseExists) ''
      config/opencode/opencode.json must not exist.
      (Detected at: ${toString publicRoot}/opencode.json)
      The public side is fragment-only — split content into one of the
      `opencode.<scope>.json` partials (meta, watcher, permission.bash,
      permission.fs, permission.web, experimental.quotaToast).
      See AGENTS.md > "opencode.json (4-tier deep merge)" for details.
    '';
    deepMergeAll (repoFragments ++ importFragments ++ privateFragments ++ [ privateOverlay ]);

  # Compute the merged AGENTS.md content respecting rulesMode:
  #   - "merged":       public + import + private rule fragments
  #   - "private_only": import + private only (public excluded)
  #   - "disabled":     empty string (caller skips writing the file)
  #
  # Filenames across all source dirs are sorted together in byte order.
  # Later sources win on filename collision, so private fragments
  # always override matching public/import fragments.
  mkAgentsContent =
    {
      rulesMode ? "merged",
      publicRulesDir,
      importRulesDirs ? [ ],
      privateRulesDir ? null,
    }:
    let
      privateRulesList = lib.optional (privateRulesDir != null) privateRulesDir;
      fragmentDirs =
        if rulesMode == "merged" then
          [ publicRulesDir ] ++ importRulesDirs ++ privateRulesList
        else if rulesMode == "private_only" then
          importRulesDirs ++ privateRulesList
        else
          [ ];
    in
    concatFiles { inherit fragmentDirs; };
in
{
  inherit
    jsonFragmentsIn
    mkMergedOpencodeJson
    mkAgentsContent
    ;
}
