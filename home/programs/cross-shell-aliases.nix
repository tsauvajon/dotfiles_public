# Cross-shell alias codegen.
#
# Define an alias once in `programs.crossShellAliases.aliases` and this
# module emits two synchronised fragments at HM build time:
#
#   ~/.config/zsh/common-aliases.zsh         (sourced from zshrc)
#   ~/.config/fish/conf.d/common-aliases.fish (auto-loaded by fish)
#
# Per-shell-only aliases (e.g. Arch pacman shorthands in fish, docker
# shortcuts in zsh) stay in the per-shell rc files. Replacement notices
# are generated as shell functions so arguments are forwarded explicitly.
#
# Fish can opt selected aliases into abbreviations with
# `programs.crossShellAliases.fishAbbreviations`. Those expand only in
# interactive fish command lines; zsh still receives normal aliases.
#
# Quoting: values are shell-quoted via lib.escapeShellArg, which emits
# POSIX single-quoted strings that work identically in zsh and fish.
{ config, lib, ... }:

let
  cfg = config.programs.crossShellAliases;

  # Sort attribute names so the generated files have a stable,
  # alphabetically ordered alias list. lib.attrNames already sorts.
  names = lib.attrNames cfg.aliases;

  fishAbbreviationNames = cfg.fishAbbreviations;
  fishCompletionWrapNames = lib.attrNames cfg.fishCompletionWraps;
  replacementNoticeNames = lib.attrNames cfg.replacementNotices;
  replacementNames = lib.filter (name: builtins.hasAttr name cfg.aliases) replacementNoticeNames;

  missingFishCompletionWraps = lib.filter (
    name: !(builtins.hasAttr name cfg.aliases)
  ) fishCompletionWrapNames;
  missingReplacementNotices = lib.filter (
    name: !(builtins.hasAttr name cfg.aliases)
  ) replacementNoticeNames;
  replacementAbbreviations = lib.filter (
    name: builtins.elem name fishAbbreviationNames
  ) replacementNoticeNames;
  missingFishAbbreviations = lib.filter (
    name: !(builtins.hasAttr name cfg.aliases)
  ) fishAbbreviationNames;

  noticeMessage = name: "dotfiles: ${name} is configured as ${cfg.replacementNotices.${name}}";

  zshLine = name: "alias ${name}=${lib.escapeShellArg cfg.aliases.${name}}";
  zshReplacementLine =
    name:
    lib.concatStringsSep "\n" [
      "unalias ${name} 2>/dev/null || true"
      "${name}() {"
      "  printf '%s\\n' ${lib.escapeShellArg (noticeMessage name)} >&2"
      "  ${cfg.aliases.${name}} \"$@\""
      "}"
    ];

  fishAliasLine = name: "alias ${name} ${lib.escapeShellArg cfg.aliases.${name}}";
  fishAbbreviationLine =
    name: "abbr --add -- ${lib.escapeShellArg name} ${lib.escapeShellArg cfg.aliases.${name}}";
  fishReplacementLine =
    name:
    lib.concatStringsSep "\n" [
      "function ${name} --description ${lib.escapeShellArg "${name} replacement via ${cfg.replacementNotices.${name}}"}"
      "  printf '%s\\n' ${lib.escapeShellArg (noticeMessage name)} >&2"
      "  ${cfg.aliases.${name}} $argv"
      "end"
    ];
  fishCompletionWrapLine =
    name:
    lib.concatStringsSep "\n" [
      "complete --erase --command ${lib.escapeShellArg name}"
      "complete --command ${lib.escapeShellArg name} --wraps ${
        lib.escapeShellArg cfg.fishCompletionWraps.${name}
      }"
    ];

  zshEntry =
    name: if builtins.elem name replacementNames then zshReplacementLine name else zshLine name;
  fishEntry =
    name:
    if builtins.elem name replacementNames then
      fishReplacementLine name
    else if builtins.elem name fishAbbreviationNames then
      fishAbbreviationLine name
    else
      fishAliasLine name;

  zshBody = lib.concatMapStringsSep "\n" zshEntry names;
  fishCompletionWrapBody =
    lib.concatMapStringsSep "\n" fishCompletionWrapLine
      fishCompletionWrapNames;
  fishBody = lib.concatStringsSep "\n" (
    lib.filter (part: part != "") [
      (lib.concatMapStringsSep "\n" fishEntry names)
      fishCompletionWrapBody
    ]
  );

  banner = ''
    # ============================================================
    # GENERATED FILE — do not edit by hand.
    # Source: home/programs/cross-shell-aliases.nix in the dotfiles
    # repo. Edit the `programs.crossShellAliases.aliases` attrset
    # instead and rerun `bash setup.sh` to regenerate.
    # ============================================================
  '';
in
{
  options.programs.crossShellAliases = {
    aliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        g = "git";
        gpl = "git pull --rebase --recurse-submodules";
      };
      description = ''
        Aliases shared between zsh and fish. Entries normally produce
        aliases in both shells; entries listed in `replacementNotices`
        produce wrapper functions that print a notice and forward args.
      '';
    };

    fishAbbreviations = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "gco" ];
      description = ''
        Alias names that should be emitted as fish abbreviations instead
        of fish aliases. Zsh always receives normal aliases.
      '';
    };

    fishCompletionWraps = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        oc = "opencode";
      };
      description = ''
        Fish completion overrides for aliases whose names collide with
        built-in fish completions. The value is the command whose
        completions should be wrapped.
      '';
    };

    replacementNotices = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        ls = "eza";
        cat = "bat";
      };
      description = ''
        Aliases that should print a short notice before executing because
        they replace another tool. The value is the replacement tool name
        shown in the notice.
      '';
    };
  };

  config = lib.mkIf (cfg.aliases != { }) {
    assertions = [
      {
        assertion = missingFishAbbreviations == [ ];
        message = "programs.crossShellAliases.fishAbbreviations contains unknown aliases: ${lib.concatStringsSep ", " missingFishAbbreviations}";
      }
      {
        assertion = missingFishCompletionWraps == [ ];
        message = "programs.crossShellAliases.fishCompletionWraps contains unknown aliases: ${lib.concatStringsSep ", " missingFishCompletionWraps}";
      }
      {
        assertion = missingReplacementNotices == [ ];
        message = "programs.crossShellAliases.replacementNotices contains unknown aliases: ${lib.concatStringsSep ", " missingReplacementNotices}";
      }
      {
        assertion = replacementAbbreviations == [ ];
        message = "programs.crossShellAliases aliases cannot be both replacement notices and fish abbreviations: ${lib.concatStringsSep ", " replacementAbbreviations}";
      }
    ];

    xdg.configFile = {
      "zsh/common-aliases.zsh".text = banner + zshBody + "\n";
      "fish/conf.d/common-aliases.fish".text = banner + fishBody + "\n";
    };
  };
}
