# Hyprland 0.55+ Lua configuration with the selected terminal's rules and
# the selected status bar (dotfiles.desktop.bar).
{
  pkgs,
  lib,
  config,
  terminal,
  ...
}:

let
  bar = config.dotfiles.desktop.bar;
  statusBarCommand =
    if bar == "hyprbaric" then "~/.nix-profile/bin/hyprbaric" else "~/.nix-profile/bin/waybar";

  # Starts only the selected bar and owns notification-daemon ownership:
  # hyprbaric ships its own freedesktop server, so it must not race mako.
  # Used for Hyprland autostart and the SUPER+SHIFT+R binding.
  statusBarScript = pkgs.writeShellScript "status-bar" ''
    ${lib.optionalString (bar == "hyprbaric") ''
      # hyprbaric owns notifications; stop mako with the bars.
      killall -q mako
    ''}
    killall -q waybar .waybar-wrapped hyprbaric
    attempts=0
    while pgrep -x waybar >/dev/null \
      || pgrep -x .waybar-wrapped >/dev/null \
      || pgrep -x hyprbaric >/dev/null \
      ${if bar == "hyprbaric" then "|| pgrep -x mako >/dev/null" else ""}; do
      if [ "$attempts" -ge 50 ]; then
        echo "status-bar: bar/notification processes did not exit" >&2
        exit 1
      fi
      sleep 0.1
      attempts=$((attempts + 1))
    done
    ${lib.optionalString (bar == "waybar") ''
      # Waybar has no notification server; ensure mako is running.
      if ! pgrep -x mako >/dev/null; then
        ~/.nix-profile/bin/mako >/dev/null 2>&1 &
      fi
    ''}
    exec ${statusBarCommand}
  '';

  hyprConfig = pkgs.runCommand "hypr-config" { } ''
    mkdir -p "$out"
    cp -R --no-preserve=mode ${../../config/hypr}/. "$out"
    substituteInPlace "$out/hyprland.lua" \
      --replace-fail '@defaultTerminalClass@' '${terminal.hyprlandClass}'
    install -Dm 0755 ${statusBarScript} "$out/status-bar"
  '';
in
lib.mkIf pkgs.stdenv.isLinux {
  xdg.configFile."hypr".source = hyprConfig;
}
