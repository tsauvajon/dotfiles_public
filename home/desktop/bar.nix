# Status-bar selection for the Linux desktop session.
#
# dotfiles.desktop.bar picks the bar Hyprland autostarts and that
# SUPER+SHIFT+R restarts. The generated ~/.config/hypr/status-bar script
# (home/desktop/hyprland.nix) manages notification ownership so hyprbaric
# and mako never race. Default: hyprbaric on x86_64-linux, waybar
# elsewhere; the Waybar config stays installed as the fallback.
{
  config,
  pkgs,
  lib,
  inputs,
  nixglNvidia ? null,
  ...
}:

let
  cfg = config.dotfiles.desktop.bar;

  # Same nixGL pattern as home/personal.nix, for hardware GL on
  # non-NixOS hosts. No-op on macOS.
  wrapWithNixGL = import ../lib/wrap-with-nixgl.nix {
    inherit pkgs nixglNvidia;
    inherit (inputs) nixgl nixgl-nixpkgs;
  };
in
{
  options.dotfiles.desktop.bar = lib.mkOption {
    type = lib.types.enum [
      "hyprbaric"
      "waybar"
    ];
    default = if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then "hyprbaric" else "waybar";
    description = ''
      Status bar autostarted with Hyprland and restarted by
      SUPER+SHIFT+R. Toggle in a host module or a private overlay module
      with `dotfiles.desktop.bar = "waybar";` and rerun ./setup.sh.
    '';
  };

  config = lib.mkIf (pkgs.stdenv.isLinux && cfg == "hyprbaric") {
    home.packages = [ (wrapWithNixGL pkgs.hyprbaric "hyprbaric") ];

    # Seed the user config.toml only when missing: hyprbaric rewrites this
    # file, so it must stay user-owned. Delete it to restore the seed.
    home.activation.seedHyprbaricConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      seedTarget="$HOME/.config/hyprbaric/config.toml"
      if [ ! -f "$seedTarget" ]; then
        $DRY_RUN_CMD mkdir -p "$(dirname "$seedTarget")"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -m 0644 ${../../config/hyprbaric/config.toml} "$seedTarget"
      fi
    '';
  };
}
