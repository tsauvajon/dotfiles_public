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
# Caveats baked into `--help` output so they are visible at runtime:
#
# - Linux: ddcutil needs the i2c-dev kernel module and the user in the
#   i2c group. NixOS: `hardware.i2c.enable = true;`. Other distros:
#   `sudo modprobe i2c-dev` + `sudo usermod -aG i2c $USER`. Home Manager
#   cannot configure this layer.
# - Apple Silicon: m1ddc cannot drive the Mac's built-in HDMI port (per
#   upstream README). USB-C / Thunderbolt to the monitor works.
# - DDC/CI direction: the command runs from the currently-active video
#   input. To switch the monitor back to a machine, that machine must
#   already be the active input. This is inherent to DDC/CI.
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

  # Backend dispatch. Each branch is a chunk of shell that consumes
  # the already-validated `$port` variable and runs the actual switch.
  backendDispatch =
    if pkgs.stdenv.isLinux then
      ''
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
  Linux        — ddcutil needs the i2c-dev kernel module loaded and
                 the user in the 'i2c' group. NixOS:
                   hardware.i2c.enable = true;
                 Other distros:
                   sudo modprobe i2c-dev
                   sudo usermod -aG i2c "$USER"

  Apple Silicon — m1ddc cannot drive the Mac's built-in HDMI port.
                  USB-C / Thunderbolt to the monitor works.

  Direction    — the command runs over the currently-active video
                 link. To switch the monitor *back* to a machine, that
                 machine must already be the active input. Inherent to
                 DDC/CI.
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
