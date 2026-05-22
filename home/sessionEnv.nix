# Cross-shell session environment variables.
#
# Define an env var once in `programs.crossShellEnv.vars` and this
# module emits two synchronised fragments at HM build time:
#
#   ~/.config/zsh/common-env.zsh             (sourced from zshrc)
#   ~/.config/fish/conf.d/common-env.fish    (auto-loaded by fish)
#
# Use `vars` for unconditional, machine-independent env vars. Keep conditional
# fragments here only when they must stay synchronized across zsh and fish.
#
# We don't use HM's built-in `home.sessionVariables` because it only
# generates the sh-format file (sourced by bash/zsh) and not a fish
# equivalent unless `programs.fish.enable = true`. Switching the fish
# config to that HM module would be a much larger refactor.
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.crossShellEnv;
  sccacheDir = "${config.home.homeDirectory}/.cache/sccache";
  sccacheClang = "${config.home.profileDirectory}/bin/sccache-clang";
  sccacheClangxx = "${config.home.profileDirectory}/bin/sccache-clang++";

  names = lib.attrNames cfg.vars;

  zshLine = name: "export ${name}=${lib.escapeShellArg cfg.vars.${name}}";
  fishLine = name: "set -gx ${name} ${lib.escapeShellArg cfg.vars.${name}}";

  zshBody = lib.concatMapStringsSep "\n" zshLine names;
  fishBody = lib.concatMapStringsSep "\n" fishLine names;

  # Cargo reads environment variables before its config-level `[env]` fallback,
  # so these wrappers take effect in managed shells without changing unmanaged
  # cargo invocations.
  nativeCacheZsh = lib.optionalString pkgs.stdenv.isDarwin ''
    if [[ "''${OPENCODE_CARGO_NATIVE_CACHE:-}" != "0" ]]; then
      if [[ -z "''${CC+x}" && -x ${lib.escapeShellArg sccacheClang} ]]; then
        export CC=${lib.escapeShellArg sccacheClang}
      fi
      if [[ -z "''${CXX+x}" && -x ${lib.escapeShellArg sccacheClangxx} ]]; then
        export CXX=${lib.escapeShellArg sccacheClangxx}
      fi
    fi
  '';

  nativeCacheFish = lib.optionalString pkgs.stdenv.isDarwin ''
    if test "$OPENCODE_CARGO_NATIVE_CACHE" != 0
        if not set -q CC; and test -x ${lib.escapeShellArg sccacheClang}
            set -gx CC ${lib.escapeShellArg sccacheClang}
        end
        if not set -q CXX; and test -x ${lib.escapeShellArg sccacheClangxx}
            set -gx CXX ${lib.escapeShellArg sccacheClangxx}
        end
    end
  '';

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
      SCCACHE_DIR = sccacheDir;
    };

    xdg.configFile = lib.mkIf (cfg.vars != { }) {
      "zsh/common-env.zsh".text = banner + zshBody + "\n" + nativeCacheZsh;
      "fish/conf.d/common-env.fish".text =
        banner + fishBody + "\n" + nativeCacheFish;
    };
  };
}
