# Linux-only Nautilus launcher that follows the focused terminal's cwd.
{
  pkgs,
  lib,
  terminal,
  ...
}:

lib.mkIf pkgs.stdenv.isLinux {
  home.packages = [
    (pkgs.writeShellApplication {
      name = "nautilus-terminal-cwd";
      runtimeInputs = [
        pkgs.hyprland
        pkgs.nautilus
        pkgs.python3
      ];
      text = ''
        cwd="$(hyprctl activewindow -j 2>/dev/null | python3 ${./nautilus-terminal-cwd.py} ${lib.escapeShellArg terminal.hyprlandClass} || true)"

        if [ ! -d "$cwd" ]; then
          cwd="$HOME"
        fi

        exec nautilus -- "$cwd"
      '';
    })
  ];

  systemd.user.services.udiskie = {
    Unit.Description = "Udiskie removable-drive automounter";
    Service = {
      ExecStart = "${pkgs.udiskie}/bin/udiskie --automount --no-tray --no-notify";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "default.target" ];
  };
}
