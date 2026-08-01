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

  # Serialize generated JSON without formatting whitespace. Source JSON stays
  # human-readable; only the merged files written to ~/.config/opencode use
  # this compact representation.
  toCompactJson = builtins.toJSON;

  # Remove disabled providers and rewrite every model assignment that
  # references one of them. Fallbacks are deliberately exact and
  # provider-local so adding a new model cannot silently select an
  # unrelated replacement.
  applyProviderGates =
    {
      config,
      providerGates,
    }:
    let
      disabledGates = lib.filterAttrs (_: gate: !gate.enable) providerGates;
      disabledProviderNames = builtins.attrNames disabledGates;

      rewriteModelReference =
        model:
        if !builtins.isString model then
          {
            value = model;
            rewritten = false;
            variantFallbacks = { };
          }
        else
          let
            providerName = lib.findFirst (name: lib.hasPrefix "${name}/" model) null disabledProviderNames;
          in
          if providerName == null then
            {
              value = model;
              rewritten = false;
              variantFallbacks = { };
            }
          else
            let
              modelId = lib.removePrefix "${providerName}/" model;
              fallback = disabledGates.${providerName}.modelFallbacks.${modelId} or null;
            in
            if fallback == null then
              throw ''
                OpenCode provider gate "${providerName}" is disabled, but model
                reference "${model}" has no fallback. Add
                programs.opencode.providerGates.${providerName}.modelFallbacks."${modelId}".
              ''
            else
              {
                value = fallback.direct;
                rewritten = true;
                variantFallbacks = fallback.variantFallbacks or { };
              };

      rewriteValue =
        name: value:
        if name == "model" || name == "small_model" then
          (rewriteModelReference value).value
        else
          rewrite value;

      rewrite =
        value:
        if builtins.isAttrs value then
          let
            modelAssignment =
              if value ? model then
                rewriteModelReference value.model
              else if value ? small_model then
                rewriteModelReference value.small_model
              else
                null;
            rewritten = lib.mapAttrs rewriteValue value;
            shouldRewriteVariant =
              value ? variant
              && modelAssignment != null
              && modelAssignment.rewritten
              && builtins.isString value.variant
              && builtins.hasAttr value.variant modelAssignment.variantFallbacks;
          in
          if shouldRewriteVariant then
            rewritten // { variant = modelAssignment.variantFallbacks.${value.variant}; }
          else
            rewritten
        else if builtins.isList value then
          map rewrite value
        else
          value;

      configWithoutProviders =
        if !(config ? provider) then
          config
        else
          let
            remainingProviders = builtins.removeAttrs config.provider disabledProviderNames;
          in
          if remainingProviders == { } then
            builtins.removeAttrs config [ "provider" ]
          else
            config // { provider = remainingProviders; };

      gatedConfig = configWithoutProviders // {
        disabled_providers = lib.unique (
          (configWithoutProviders.disabled_providers or [ ]) ++ disabledProviderNames
        );
      };
    in
    if disabledProviderNames == [ ] then config else rewrite gatedConfig;

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
  # fragment filter and violate the contract implemented below.
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
      The public side is fragment-only — split content into per-scope
      `opencode.<scope>.json` partials (for example meta, models, watcher,
      permission.*, agent, provider.*, experimental.*).
      See `mkMergedOpencodeJson` in home/lib/opencode-merge.nix and the
      fragments under config/opencode/ for the canonical merge contract.
    '';
    deepMergeAll (repoFragments ++ importFragments ++ privateFragments ++ [ privateOverlay ]);

  # Compute the merged `package.json` for ~/.config/opencode.
  #
  # The public manifest declares every plugin dependency except
  # `@opencode-ai/plugin`, whose version is injected by the caller
  # (`home/opencode.nix` passes `pkgs.opencode.version`) so the plugin
  # SDK always matches the installed OpenCode binary. `opencodePin` in
  # flake.nix is therefore the single version source for a bump. The
  # optional private overlay merges last and may deliberately override
  # the injected version.
  #
  # The merge fails fast (via assertMsg) if the public manifest pins
  # `@opencode-ai/plugin`: the injected version would silently win,
  # turning the committed pin into a lie.
  mkMergedPackage =
    {
      publicRoot,
      privatePackageFile ? null,
      pluginVersion,
    }:
    let
      publicPackage = readJsonOr (publicRoot + "/package.json") { };
      privatePackage = readJsonOr privatePackageFile { };
      publicPluginPin = lib.attrByPath [ "dependencies" "@opencode-ai/plugin" ] null publicPackage;
    in
    assert lib.assertMsg (publicPluginPin == null) ''
      config/opencode/package.json must not pin @opencode-ai/plugin.
      (Found "${toString publicPluginPin}" at ${toString publicRoot}/package.json)
      The plugin version is injected from the installed OpenCode package
      (opencodePin in flake.nix), so the SDK always matches the binary.
      Remove the dependency from the public manifest; use the private
      overlay package.json for a deliberate version skew.
    '';
    deepMergeAll [
      publicPackage
      { dependencies."@opencode-ai/plugin" = pluginVersion; }
      privatePackage
    ];

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
    applyProviderGates
    jsonFragmentsIn
    mkMergedOpencodeJson
    mkMergedPackage
    mkAgentsContent
    toCompactJson
    ;
}
