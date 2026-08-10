# OpenCode public/private overlay merges.
#
# - `commands`, `skills`, `agents`, `plugins`: per-tree directory merge,
#   private wins on collision. Built by `lib/merge-dirs.nix`.
# - `AGENTS.md`: cross-source fragment merge. Public rules in
#   `config/opencode/rules/` and private rules in
#   `~/.config/dotfiles/config/opencode/rules/` are collected together,
#   filename collisions resolve in favor of the private overlay, and
#   the surviving fragments are sorted by filename in byte order
#   (LC_ALL=C). Built by `lib/concat-files.nix`.
# - `opencode.*.json` partials and `package.json`: deep JSON merge,
#   private wins. The public side is fragment-only — there is no
#   `config/opencode/opencode.json`; sections live in per-scope
#   `opencode.<scope>.json` partials (for example meta, models, watcher,
#   permission.*, agent, provider.*, experimental.*). Built by
#   `lib/deep-merge-json.nix`.
#   `package.json` additionally injects the `@opencode-ai/plugin`
#   version from `pkgs.opencode.version` (i.e. `opencodePin` in
#   flake.nix), so the public manifest never pins it.
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

  mergeDirs = import ./lib/merge-dirs.nix { inherit pkgs lib; };
  inherit (import ./lib/opencode-merge.nix { inherit lib; })
    applyProviderGates
    mkMergedOpencodeJson
    mkMergedPackage
    mkAgentsContent
    toCompactJson
    ;

  publicRoot = ../config/opencode;
  # Every field of `inputs.private.opencode` is optional. A user's
  # private flake.nix may omit the entire `opencode` attribute (the
  # placeholder does), in which case we fall back to an empty attrset
  # and every consumed path defaults to its standard subpath under
  # `<private flake>/config/opencode/` — see `defaultPrivateSubpath` below.
  privatePaths = inputs.private.opencode or { };

  # Standard layout: every private OpenCode overlay lives under
  # `<private flake outPath>/config/opencode/<name>` (e.g. `commands/`,
  # `skills/`, `opencode.json`). We expose this dir explicitly so the
  # discovery root stays stable even when a downstream private flake
  # overrides individual fields with non-standard locations.
  privateOpencodeDir = inputs.private.outPath + "/config/opencode";

  # Resolve a private subpath to its absolute Nix path if it exists,
  # else null. Used to default each `*Dir` / `*File` field below so
  # users do not need to enumerate the standard layout in their
  # private flake — dropping a file under `<private>/config/opencode/<name>`
  # is enough to wire it into the merge.
  defaultPrivateSubpath =
    sub:
    let
      p = privateOpencodeDir + "/${sub}";
    in
    if builtins.pathExists p then p else null;

  # External imports staged by setup.sh into
  # ~/.config/dotfiles/opencode-imports/<name>/. The private flake
  # declares `opencode.imports` and the HM build derives the staged
  # directories from each import name. `importsDirs` is an escape
  # hatch for hand-written private flakes.
  declaredImports = privatePaths.imports or [ ];
  stagedImportsDirs = map (i: inputs.private.outPath + "/opencode-imports/${i.name}") declaredImports;
  importsDirs = stagedImportsDirs ++ (privatePaths.importsDirs or [ ]);

  # Each *Dir / *File field is optional in the private flake. When
  # omitted, fall back to the standard subpath under
  # `<private>/config/opencode/<name>`. Setting a field to `null` explicitly
  # disables the overlay even if the standard subpath exists; setting
  # it to a custom path overrides the default location.
  privateCommandsDir = privatePaths.commandsDir or (defaultPrivateSubpath "commands");
  privateSkillsDir = privatePaths.skillsDir or (defaultPrivateSubpath "skills");
  privateAgentsDir = privatePaths.agentsDir or (defaultPrivateSubpath "agents");
  privatePluginsDir = privatePaths.pluginsDir or (defaultPrivateSubpath "plugins");
  privateRulesDir = privatePaths.rulesDir or (defaultPrivateSubpath "rules");
  privatePrimaryRulesDir = privatePaths.primaryRulesDir or (defaultPrivateSubpath "primary-rules");
  privateConfigFile = privatePaths.configFile or (defaultPrivateSubpath "opencode.json");
  privatePackageFile = privatePaths.packageFile or (defaultPrivateSubpath "package.json");

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
  importPrimaryRulesDirs = importDirsFor "primary-rules";

  # Keep committed JSON readable while writing compact merged output.
  compactJsonFile = name: value: pkgs.writeText name (toCompactJson value);

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
      excludeNames ? [ ],
    }:
    mergeDirs {
      name = "opencode-${name}";
      inherit excludeNames;
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
    excludeNames = cfg.excludedCommands;
  };
  mergedSkills = mkMergedDir {
    name = "skills";
    privatePath = privateSkillsDir;
    importDirs = importSkillsDirs;
    excludeNames = cfg.excludedSkills;
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

  # AGENTS.md content respecting cfg.rulesMode. The pure merge logic
  # lives in lib/opencode-merge.nix so it can be unit-tested with
  # synthetic fixtures.
  agentsContent = mkAgentsContent {
    rulesMode = cfg.rulesMode;
    publicRulesDir = publicRoot + "/rules";
    inherit importRulesDirs;
    inherit privateRulesDir;
  };

  primaryAgentsContent = mkAgentsContent {
    rulesMode = cfg.rulesMode;
    publicRulesDir = publicRoot + "/primary-rules";
    importRulesDirs = importPrimaryRulesDirs;
    privateRulesDir = privatePrimaryRulesDir;
  };

  # opencode.json: 4-tier deep merge. The pure merge logic (including
  # the publicBaseExists guardrail) lives in lib/opencode-merge.nix.
  # JSON fragments live next to the private overlay's `config/opencode/` dir
  # (see `privateOpencodeDir` above) so the discovery root stays stable
  # even when `configFile` is overridden by a downstream private flake.
  mergedJson = applyProviderGates {
    config = mkMergedOpencodeJson {
      inherit publicRoot importsDirs privateOpencodeDir;
      inherit privateConfigFile;
    };
    providerGates = cfg.providerGates;
  };

  # package.json: public manifest + injected `@opencode-ai/plugin` pin
  # (from the installed OpenCode package version, i.e. `opencodePin` in
  # flake.nix) + optional private overlay (wins, for deliberate skew).
  # Keeping the plugin version out of the committed manifest makes the
  # flake pin the single place to bump.
  mergedPackage = mkMergedPackage {
    inherit publicRoot privatePackageFile;
    pluginVersion = pkgs.opencode.version;
  };

  opencodeAllowedEntries = [
    ".gitignore"
    "AGENTS.md"
    "agents"
    "bun.lock"
    "bun.lockb"
    "commands"
    "node_modules"
    "opencode*.db"
    "opencode*.db-*"
    "opencode.json"
    "package-lock.json"
    "package.json"
    "plugins"
    "primary-context.md"
    "skills"
    "themes"
    "tui.json"
  ];

  opencodeAllowedEntryCases = lib.concatMapStringsSep "\n" (
    name: "          ${name}) ;;"
  ) opencodeAllowedEntries;
in
{
  options.programs.opencode = {
    providerGates = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether this OpenCode provider and its model assignments remain enabled.";
            };

            modelFallbacks = lib.mkOption {
              type = lib.types.attrsOf (
                lib.types.submodule {
                  options = {
                    direct = lib.mkOption {
                      type = lib.types.str;
                      description = "Direct provider/model replacement used when the provider gate is disabled.";
                    };

                    variantFallbacks = lib.mkOption {
                      type = lib.types.attrsOf lib.types.str;
                      default = { };
                      description = "Variant replacements applied alongside this model fallback.";
                    };
                  };
                }
              );
              default = { };
              description = "Fallbacks keyed by provider-local model ID.";
            };
          };
        }
      );
      default = { };
      description = "Provider availability gates and exact model fallbacks for generated OpenCode config.";
    };

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

    excludedCommands = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Top-level OpenCode command filenames to omit from the generated commands directory.";
    };

    excludedSkills = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Top-level OpenCode skill directory names to omit from the generated skills directory.";
    };
  };

  config = {
    xdg.configFile = lib.mkMerge [
      {
        "opencode/commands".source = mergedCommands;
        "opencode/skills".source = mergedSkills;
        "opencode/agents".source = mergedAgents;
        "opencode/plugins".source = mergedPlugins;
        "opencode/themes/catppuccin-mocha-lavender.json".source =
          "${inputs.catppuccin-opencode}/themes/mocha/catppuccin-mocha-lavender.json";
        "opencode/opencode.json".source = compactJsonFile "opencode.json" mergedJson;
        # tui.json is a separate OpenCode file (different $schema) — not
        # part of the opencode.json deep-merge. Symlinked verbatim from
        # the public source.
        "opencode/tui.json".source = publicRoot + "/tui.json";
      }
      (lib.mkIf (cfg.rulesMode != "disabled") {
        "opencode/AGENTS.md".text = agentsContent;
        "opencode/primary-context.md".text = primaryAgentsContent;
      })
      {
        # The public package.json is committed and non-empty, so
        # mergedPackage always has content. Always emit the file and
        # always run the bun-install activation.
        "opencode/package.json".source = compactJsonFile "opencode-package.json" mergedPackage;
      }
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
    home.activation = {
      opencodeCheckDuplicateSkillNames = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        skills_dir="${config.xdg.configHome}/opencode/skills"
        if [ -d "$skills_dir" ]; then
          names_file="$(${pkgs.coreutils}/bin/mktemp)"
          trap '${pkgs.coreutils}/bin/rm -f "$names_file"' EXIT

          while IFS= read -r skill_file; do
            name="$(${pkgs.gawk}/bin/awk '
              BEGIN { in_frontmatter = 0 }
              NR == 1 && $0 == "---" { in_frontmatter = 1; next }
              in_frontmatter && $0 == "---" { exit }
              in_frontmatter && $0 ~ /^name:[[:space:]]*/ {
                sub(/^name:[[:space:]]*/, "")
                gsub(/^"|"$/, "")
                print
                exit
              }
            ' "$skill_file")"
            [ -n "$name" ] || continue
            printf '%s\t%s\n' "$name" "$skill_file" >>"$names_file"
          done < <(${pkgs.findutils}/bin/find -L "$skills_dir" -mindepth 2 -maxdepth 2 -name SKILL.md -type f)

          duplicates="$(${pkgs.coreutils}/bin/cut -f1 "$names_file" | ${pkgs.coreutils}/bin/sort | ${pkgs.coreutils}/bin/uniq -d)"
          if [ -n "$duplicates" ]; then
            printf '%s\n' "Duplicate OpenCode skill names detected:" >&2
            while IFS= read -r duplicate; do
              [ -n "$duplicate" ] || continue
              ${pkgs.gnugrep}/bin/grep -F "''${duplicate}$(printf '\t')" "$names_file" >&2 || true
            done <<EOF
$duplicates
EOF
            exit 1
          fi
        fi
      '';

      opencodeCheckUnmanaged = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        dir="${config.xdg.configHome}/opencode"
        unmanaged=""
        if [ -d "$dir" ]; then
          for path in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
            [ -e "$path" ] || [ -L "$path" ] || continue
            name="''${path##*/}"
            case "$name" in
${opencodeAllowedEntryCases}
              *)
                if [ -z "$unmanaged" ]; then
                  unmanaged="  $name"
                else
                  unmanaged="$unmanaged
  $name"
                fi
                ;;
            esac
          done
        fi

        if [ -n "$unmanaged" ]; then
          printf '%s\n' "Found unmanaged OpenCode config under $dir:" >&2
          printf '%s\n' "$unmanaged" >&2
          printf '%s\n' "Move it into dotfiles/private overlay or remove it before activating." >&2
          exit 1
        fi
      '';

      opencodeBunInstall = lib.hm.dag.entryAfter [ "opencodeCheckUnmanaged" ] ''
        pkg="${config.xdg.configHome}/opencode/package.json"
        marker="${config.xdg.cacheHome}/dotfiles/opencode-package.sha256"
        ${pkgs.coreutils}/bin/mkdir -p "$(dirname "$marker")"
        if [ -f "$pkg" ]; then
          new_hash=$(${pkgs.coreutils}/bin/sha256sum "$pkg" | ${pkgs.coreutils}/bin/cut -d' ' -f1)
          old_hash=$(${pkgs.coreutils}/bin/cat "$marker" 2>/dev/null || true)
          if [ "$new_hash" != "$old_hash" ]; then
            echo "==> opencode/package.json changed; running bun install"
            if ( cd "$(dirname "$pkg")" && ${pkgs.bun}/bin/bun install ); then
              printf '%s\n' "$new_hash" > "$marker"
            else
              echo "warning: bun install failed for $pkg; leaving marker unchanged so the next activation retries" >&2
            fi
          fi
        fi
      '';
    };
  };
}
