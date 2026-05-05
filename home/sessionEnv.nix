# Cross-shell session environment variables.
#
# Define an env var once in `programs.crossShellEnv.vars` and this
# module emits two synchronised fragments at HM build time:
#
#   ~/.config/zsh/common-env.zsh             (sourced from zshrc)
#   ~/.config/fish/conf.d/common-env.fish    (auto-loaded by fish)
#
# Use this for unconditional, machine-independent env vars only.
# Conditional logic (e.g. only-on-Wayland) lives in per-shell rc files.
#
# We don't use HM's built-in `home.sessionVariables` because it only
# generates the sh-format file (sourced by bash/zsh) and not a fish
# equivalent unless `programs.fish.enable = true`. Switching the fish
# config to that HM module would be a much larger refactor.
{ config, lib, ... }:

let
  cfg = config.programs.crossShellEnv;

  names = lib.attrNames cfg.vars;

  zshLine = name: "export ${name}=${lib.escapeShellArg cfg.vars.${name}}";
  fishLine = name: "set -gx ${name} ${lib.escapeShellArg cfg.vars.${name}}";

  zshBody = lib.concatMapStringsSep "\n" zshLine names;
  fishBody = lib.concatMapStringsSep "\n" fishLine names;

  banner = ''
    # ============================================================
    # GENERATED FILE — do not edit by hand.
    # Source: home/sessionEnv.nix in the dotfiles repo. Edit the
    # `programs.crossShellEnv.vars` attrset and rerun setup.sh to
    # regenerate.
    # ============================================================
  '';
in
{
  options.programs.crossShellEnv = {
    vars = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        BAT_THEME = "Catppuccin Mocha";
        EDITOR = "hx";
      };
      description = ''
        Environment variables shared between zsh and fish. Each entry
        produces one `export NAME=VALUE` (zsh) or
        `set -gx NAME VALUE` (fish) line in the generated fragment.
      '';
    };
  };

  config = {
    programs.crossShellEnv.vars = {
      # bat (cat replacement) theme — Catppuccin Mocha to match the
      # rest of the terminal aesthetic.
      BAT_THEME = "Catppuccin Mocha";
    };

    xdg.configFile = lib.mkIf (cfg.vars != { }) {
      "zsh/common-env.zsh".text = banner + zshBody + "\n";
      "fish/conf.d/common-env.fish".text = banner + fishBody + "\n";
    };
  };
}
