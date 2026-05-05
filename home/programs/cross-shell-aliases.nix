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
# Quoting: values are shell-quoted via lib.escapeShellArg, which emits
# POSIX single-quoted strings that work identically in zsh and fish.
{ config, lib, ... }:

let
  cfg = config.programs.crossShellAliases;

  # Sort attribute names so the generated files have a stable,
  # alphabetically ordered alias list. lib.attrNames already sorts.
  names = lib.attrNames cfg.aliases;

  zshLine = name: "alias ${name}=${lib.escapeShellArg cfg.aliases.${name}}";
  fishLine = name: "alias ${name} ${lib.escapeShellArg cfg.aliases.${name}}";

  zshBody = lib.concatMapStringsSep "\n" zshLine names;
  fishBody = lib.concatMapStringsSep "\n" fishLine names;

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
  };

  config = lib.mkIf (cfg.aliases != { }) {
    xdg.configFile = {
      "zsh/common-aliases.zsh".text = banner + zshBody + "\n";
      "fish/conf.d/common-aliases.fish".text = banner + fishBody + "\n";
    };
  };
}
