# Cross-shell alias codegen.
#
# Define an alias once in `programs.crossShellAliases.aliases` and this
# module emits two synchronised fragments at HM build time:
#
#   ~/.config/zsh/common-aliases.zsh         (sourced from zshrc)
#   ~/.config/fish/conf.d/common-aliases.fish (auto-loaded by fish)
#
# Per-shell-only aliases (e.g. Arch pacman shorthands in fish, docker
# shortcuts in zsh) stay in the per-shell rc files. Functions also
# stay per-shell because the syntax differs between shells.
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
  fishAliasNames = lib.filter (name: !(builtins.elem name fishAbbreviationNames)) names;
  missingFishAbbreviations = lib.filter (
    name: !(builtins.hasAttr name cfg.aliases)
  ) fishAbbreviationNames;

  zshLine = name: "alias ${name}=${lib.escapeShellArg cfg.aliases.${name}}";
  fishAliasLine = name: "alias ${name} ${lib.escapeShellArg cfg.aliases.${name}}";
  fishAbbreviationLine =
    name: "abbr --add -- ${lib.escapeShellArg name} ${lib.escapeShellArg cfg.aliases.${name}}";

  zshBody = lib.concatMapStringsSep "\n" zshLine names;
  fishAliasBody = lib.concatMapStringsSep "\n" fishAliasLine fishAliasNames;
  fishAbbreviationBody = lib.concatMapStringsSep "\n" fishAbbreviationLine fishAbbreviationNames;
  fishBody = lib.concatStringsSep "\n" (
    lib.filter (part: part != "") [
      fishAliasBody
      fishAbbreviationBody
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
        Aliases shared between zsh and fish. Each entry produces one
        `alias name=value` line in both shells' generated fragment.
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
  };

  config = lib.mkIf (cfg.aliases != { }) {
    assertions = [
      {
        assertion = missingFishAbbreviations == [ ];
        message = "programs.crossShellAliases.fishAbbreviations contains unknown aliases: ${lib.concatStringsSep ", " missingFishAbbreviations}";
      }
    ];

    xdg.configFile = {
      "zsh/common-aliases.zsh".text = banner + zshBody + "\n";
      "fish/conf.d/common-aliases.fish".text = banner + fishBody + "\n";
    };
  };
}
