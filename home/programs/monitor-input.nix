# `monitor-input` — switch the Dell U4025QW input source via DDC/CI.
#
# Wraps a platform-appropriate backend so that Hyprland (Linux) and
# AeroSpace (macOS) keybinds can call the same `monitor-input <port>`
# command:
#
#   monitor-input dp           # DisplayPort   (VCP 0x60 = 0x0f / 15)
#   monitor-input hdmi         # HDMI 1        (VCP 0x60 = 0x11 / 17)
#   monitor-input thunderbolt  # USB-C / TB    (VCP 0x60 = 0x1b / 27)
#
# Backends, selected at Nix-build-time:
#
#   Linux           — pkgs.ddcutil
#   aarch64-darwin  — pkgs.m1ddc
#   x86_64-darwin   — kfix/ddcctl, packaged from the `ddcctl-src` flake
#                     input (m1ddc is aarch64-only)
#
# On Linux the wrapper self-diagnoses the system-level i2c prerequisites
# before invoking ddcutil — that layer (i2c-dev kernel module + i2c
# group membership) is outside Home Manager's reach, so a fresh box
# would otherwise fail with a confusing libi2c error from ddcutil.
#
# Caveats baked into `--help`:
#
# - Linux: ddcutil needs the i2c-dev kernel module and the user in the
#   i2c group. NixOS: `hardware.i2c.enable = true;`. Other distros:
#   `sudo modprobe i2c-dev` + `sudo usermod -aG i2c $USER`.
# - Apple Silicon: m1ddc sends DDC commands over the active video link,
#   so connect via Thunderbolt/USB-C. The built-in HDMI port on base
#   M1 / entry M2 Macs cannot send DDC, but Thunderbolt-connected Macs
#   can still tell the monitor to switch *to* HDMI input.
# - DDC/CI direction: the command runs over the currently-active link.
#   To switch the monitor back to a machine, that machine must already
#   be the active input. This is inherent to DDC/CI.
{
  pkgs,
  lib,
  inputs,
  ...
}:

let
  # Build ddcctl only when targeting x86_64-darwin so the derivation does
  # not evaluate (and the upstream source is not pulled into the closure)
  # on Linux or Apple Silicon hosts.
  ddcctl =
    if pkgs.stdenv.isDarwin && pkgs.stdenv.isx86_64 then
      pkgs.callPackage ../lib/ddcctl.nix { src = inputs.ddcctl-src; }
    else
      null;

  # Linux-only sanity check: bail with a clear actionable message when
  # /dev/i2c-* devices are missing or unreadable. ddcutil's own error
  # message ("Display not found" / "No /dev/i2c devices exist") is much
  # less actionable for someone who just provisioned a fresh machine.
  #
  # Heredoc bodies are intentionally column-0 so the rendered message is
  # not prefixed with leading whitespace.
  linuxI2cCheck = ''
        shopt -s nullglob
        i2c_devs=(/dev/i2c-*)
        shopt -u nullglob
        if [ ''${#i2c_devs[@]} -eq 0 ]; then
          cat >&2 <<'EOF'
    monitor-input: no /dev/i2c-* devices found.
    The i2c-dev kernel module is not loaded. To fix:

      sudo modprobe i2c-dev
      echo i2c-dev | sudo tee /etc/modules-load.d/i2c.conf  # persist across reboots

    NixOS users: set `hardware.i2c.enable = true;` in your system config.
    EOF
          exit 1
        fi
        i2c_ok=0
        for dev in "''${i2c_devs[@]}"; do
          if [ -r "$dev" ] && [ -w "$dev" ]; then
            i2c_ok=1
            break
          fi
        done
        if [ "$i2c_ok" -eq 0 ]; then
          cat >&2 <<EOF
    monitor-input: /dev/i2c-* exists but is not readable/writable by $USER.
    Add yourself to the i2c group:

      sudo usermod -aG i2c "$USER"

    Then log out and back in (or run 'newgrp i2c') for the membership
    to take effect.
    EOF
          exit 1
        fi
  '';

  # Backend dispatch. Each branch is a chunk of shell that consumes
  # the already-validated `$port` variable and runs the actual switch.
  backendDispatch =
    if pkgs.stdenv.isLinux then
      ''
        ${linuxI2cCheck}
        case "$port" in
          dp)          ${pkgs.ddcutil}/bin/ddcutil setvcp 60 0x0f ;;
          hdmi)        ${pkgs.ddcutil}/bin/ddcutil setvcp 60 0x11 ;;
          thunderbolt) ${pkgs.ddcutil}/bin/ddcutil setvcp 60 0x1b ;;
        esac
      ''
    else if pkgs.stdenv.isDarwin && pkgs.stdenv.isAarch64 then
      ''
        case "$port" in
          dp)          ${pkgs.m1ddc}/bin/m1ddc set input 15 ;;
          hdmi)        ${pkgs.m1ddc}/bin/m1ddc set input 17 ;;
          thunderbolt) ${pkgs.m1ddc}/bin/m1ddc set input 27 ;;
        esac
      ''
    else if pkgs.stdenv.isDarwin && pkgs.stdenv.isx86_64 then
      ''
        case "$port" in
          dp)          ${ddcctl}/bin/ddcctl -d 1 -i 15 ;;
          hdmi)        ${ddcctl}/bin/ddcctl -d 1 -i 17 ;;
          thunderbolt) ${ddcctl}/bin/ddcctl -d 1 -i 27 ;;
        esac
      ''
    else
      throw "monitor-input: unsupported platform ${pkgs.stdenv.hostPlatform.system}";
in
{
  home.packages = [
    (pkgs.writeShellApplication {
      name = "monitor-input";
      text = ''
        usage() {
          cat >&2 <<'EOF'
Usage: monitor-input <dp|hdmi|thunderbolt>

Switch the Dell U4025QW input source via DDC/CI.

Caveats:
  Linux         — ddcutil needs the i2c-dev kernel module loaded
                  and the user in the 'i2c' group. NixOS:
                    hardware.i2c.enable = true;
                  Other distros:
                    sudo modprobe i2c-dev
                    sudo usermod -aG i2c "$USER"
                  The wrapper self-diagnoses these on each run.

  Apple Silicon — DDC is sent over the active video link, so
                  connect via Thunderbolt/USB-C. The built-in
                  HDMI port on base M1 / entry M2 Macs cannot
                  send DDC, but Thunderbolt-connected Macs can
                  still tell the monitor to switch *to* HDMI.

  Direction     — the command runs over the currently-active
                  link. To switch the monitor *back* to a
                  machine, that machine must already be the
                  active input. Inherent to DDC/CI.
EOF
          exit 2
        }

        if [ "$#" -ne 1 ]; then
          usage
        fi

        port="$1"
        case "$port" in
          dp|hdmi|thunderbolt) ;;
          -h|--help) usage ;;
          *) usage ;;
        esac

        ${backendDispatch}
      '';
    })
  ];
}
