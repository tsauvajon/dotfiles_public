# Linux Host Tasks

These follow-ups need a real Linux workstation. The macOS host can evaluate the
Linux Home Manager graph, but it cannot exercise the compositor startup path,
NVIDIA hardware, or Linux-native checks.

## Import `start-hyprland`

`start-hyprland` currently exists only on the Linux host. It is referenced by
`config/shell/profile` and `config/shell/fish_profile`, so keep the binary name
unchanged when importing it.

On the Linux host:

1. Locate the private copy:

   ```sh
   command -v start-hyprland
   ```

2. Review the script for secrets, absolute host paths, and machine-specific
   assumptions before copying any content into the public repo.
3. Add it as a Linux-only `writeShellApplication` under `home/desktop/`, keeping
   the executable name `start-hyprland` so the existing profile hooks continue to
   work unchanged.
4. Consider folding `config/wayland-env.sh` into the new application as the
   single pre-compositor environment source. Today `wayland-env.sh` and
   `config/hypr/hyprland.lua` are comment-synced duplicates.
5. Rerun `bash setup.sh` on the Linux host and verify a fresh login still starts
   Hyprland.
6. Delete the private copy once the Home Manager-managed binary is active.

## NVIDIA nixGL checks

Verify `scripts/nixgl-nvidia-doctor.sh` against the new
`_module.args.nixglNvidia` attrset shape on real NVIDIA hardware.

On the next NVIDIA driver bump, use the helper to regenerate the paste template:

```sh
scripts/nvidia-driver-hash.sh <driver-version>
```

## Login shell sanity check

Sanity-check that interactive bash logins on tty1 reach both the Hyprland
autostart and tmux auto-attach. The `.bash_profile` → `.profile` chain has been
fixed; previously `.profile` was dead for bash logins.

## Optional Linux flake checks

Build the Linux checks on the Linux host when time allows:

```sh
nix flake check --override-input private path:$HOME/.config/dotfiles
```

This validates the GNU loader gating on binary packages and the new script tests
on Linux. The macOS machine only exercises the `aarch64-darwin` checks locally.

## Hyprland clipboard and file-manager checks

After activating these dotfiles on the Linux host:

1. Run `wev` and confirm physical left Alt reports `Mod1`/`ALT`, while right Alt
   reports `Mod5`/AltGr and still enters international characters.
2. In a GUI application, verify left Alt+C/V copy and paste through Ctrl+C/V.
   In Alacritty, Kitty, Foot, and the Yazi terminal, verify the same keys use the
   terminal-safe Ctrl+Insert/Shift+Insert behavior (including inside a shell).
3. Confirm existing Super+V still toggles the focused window's floating state.
4. Confirm Super+W still opens Yazi, Super+Shift+F opens Nautilus at home, and
   Super+Shift+Alt+F opens Nautilus at the focused terminal/Yazi directory. Also
   try the CWD shortcut from a GUI window and confirm it safely falls back home.
5. Select a previewable file in Nautilus and press Space to verify Sushi.
6. Confirm `systemctl --user status udiskie` is healthy, then attach a removable
   drive and verify it mounts without a tray icon or notification.
