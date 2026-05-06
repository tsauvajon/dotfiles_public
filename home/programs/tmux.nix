# Tmux configuration via Home Manager.
#
# `config/tmux/tmux.conf` is the source of truth. This module:
# 1. Strips TPM-only lines from the conf (`set -g @plugin '...'` and
#    `run ~/.tmux/plugins/...`).
# 2. Rewrites the absolute `~/.tmux/plugins/tmux-cpu/...` path to its
#    Nix-managed equivalent.
# 3. Renders the result in the FIRST plugin's pre-load extraConfig so
#    catppuccin / resurrect / continuum / cpu variables are all set
#    before any plugin loads.
#
# Plugins in the `plugins` list load in order. `#{E:@catppuccin_*}`
# substitutions in status-line config are evaluated lazily at render
# time, so they work even though they appear in extraConfig before
# catppuccin loads.
{ pkgs, lib, ... }:

let
  cpuPlugin = pkgs.tmuxPlugins.cpu;

  rawConf = builtins.readFile ../../config/tmux/tmux.conf;

  # Drop TPM-only directives that don't apply under HM. HM manages
  # plugin discovery itself, so `set -g @plugin '...'` and the manual
  # `run ~/.tmux/plugins/...` lines are noise.
  conf =
    let
      lines = lib.splitString "\n" rawConf;
      keep =
        line:
        !(
          lib.hasPrefix "set -g @plugin '" line
          || lib.hasPrefix "run ~/.tmux/plugins/" line
        );
    in
    lib.concatStringsSep "\n" (lib.filter keep lines);

  # Rewrite the inline cpu_percentage.sh path to the Nix-managed
  # plugin location.
  preparedConf = lib.replaceStrings
    [ "~/.tmux/plugins/tmux-cpu/scripts/cpu_percentage.sh" ]
    [ "${cpuPlugin}/share/tmux-plugins/cpu/scripts/cpu_percentage.sh" ]
    conf;
in
{
  programs.tmux = {
    enable = true;

    plugins = [
      {
        # The first plugin's extraConfig is rendered before ANY plugin
        # loads, so we use it as a global "before plugins" hook for
        # all variable settings (catppuccin flavor, resurrect/
        # continuum behaviour, status-line templates).
        plugin = pkgs.tmuxPlugins.resurrect;
        extraConfig = preparedConf;
      }
      pkgs.tmuxPlugins.continuum
      pkgs.tmuxPlugins.catppuccin
      cpuPlugin
    ];
  };
}
