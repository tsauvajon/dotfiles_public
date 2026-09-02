#!/usr/bin/env python3
"""Focused static checks for literal Hyprland desktop wiring."""

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path


root = Path(sys.argv[1])
hypr = (root / "config/hypr/hyprland.lua").read_text()
cheatsheet = (root / "config/waybar/scripts/cheatsheet.py").read_text()
launcher = root / "home/desktop/nautilus-terminal-cwd.py"
compile(launcher.read_text(), str(launcher), "exec")


def normalize_chord(chord: str) -> str:
    recognized_modifiers = {"ALT", "CTRL", "MOD1", "MOD2", "MOD3", "MOD4", "MOD5", "SHIFT", "SUPER"}
    parts = [part.strip().upper() for part in chord.split("+")]
    modifiers = sorted(part for part in parts if part in recognized_modifiers)
    keys = [part for part in parts if part not in recognized_modifiers]
    return "+".join([*modifiers, *keys])

# Dynamic loop bindings are intentionally outside this small parser. A release
# binding may repeat its press chord, but two literal press bindings may not.
literal_press_bindings: dict[str, int] = {}
for line_number, line in enumerate(hypr.splitlines(), 1):
    match = re.match(r'^hl\.bind\("([^"]+)"', line)
    is_release = re.search(r"\brelease\s*=\s*true\b", line) is not None
    if match and not is_release:
        chord = normalize_chord(match.group(1))
        if chord in literal_press_bindings:
            first = literal_press_bindings[chord]
            raise SystemExit(f"duplicate literal Hyprland chord {chord}: lines {first} and {line_number}")
        literal_press_bindings[chord] = line_number

critical_bindings = {
    "ALT + C": ('"ALT + C / V": "Copy / Paste"',),
    "ALT + V": ('"ALT + C / V": "Copy / Paste"',),
    "SUPER + V": ('"SUPER + V": "Toggle Floating"',),
    "SUPER + W": ('"SUPER + W": "Yazi File Manager"',),
    "SUPER + SHIFT + F": ('"SUPER + SHIFT + F": "Nautilus Home"',),
    "SUPER + SHIFT + ALT + F": ('"SUPER + SHIFT + ALT + F": "Nautilus at Terminal CWD"',),
    "SUPER + C": ('"SUPER + C": "Toggle Center Layout"',),
    "SUPER + O": ('"SUPER + O": "Obsidian"',),
}
for chord, cheat_entries in critical_bindings.items():
    if normalize_chord(chord) not in literal_press_bindings:
        raise SystemExit(f"missing critical literal Hyprland binding: {chord}")
    for entry in cheat_entries:
        if entry not in cheatsheet:
            raise SystemExit(f"cheatsheet is stale for {chord}: missing {entry}")

if "hl.send_key_state" in hypr:
    raise SystemExit("clipboard helper must not call top-level hl.send_key_state")
if "hl.dispatch(hl.dsp.send_key_state" not in hypr:
    raise SystemExit("clipboard helper must dispatch hl.dsp.send_key_state")
if not re.search(r'hl\.dispatch\(hl\.dsp\.send_key_state\(\{[^}]*state\s*=\s*"down"', hypr):
    raise SystemExit("clipboard helper must dispatch key-down immediately")
if not re.search(r'hl\.timer\(function\(\).*timeout\s*=\s*50.*type\s*=\s*"oneshot"', hypr, re.DOTALL):
    raise SystemExit("clipboard helper must release keys with a 50ms oneshot timer")
if not re.search(r'hl\.timer\(function\(\).*send_key_state\(\{[^}]*state\s*=\s*"up"', hypr, re.DOTALL):
    raise SystemExit("clipboard timer must dispatch key-up")
if re.search(r"send_key_state\(\{[^}]*\bwindow\s*=", hypr):
    raise SystemExit("clipboard send_key_state must use the active target implicitly")

with tempfile.TemporaryDirectory() as temporary_home:
    environment = {**os.environ, "HOME": temporary_home}
    for active_window in ("null", '{"class": "firefox", "pid": 1}'):
        result = subprocess.run(
            [sys.executable, str(launcher), "Alacritty"],
            input=active_window,
            text=True,
            capture_output=True,
            check=True,
            env=environment,
        )
        if result.stdout.strip() != temporary_home:
            raise SystemExit(f"Nautilus launcher did not fall back to HOME for {active_window}")

if sys.platform.startswith("linux"):
    result = subprocess.run(
        [sys.executable, str(launcher), "Alacritty"],
        input=f'{{"class": "Alacritty", "pid": {os.getpid()}}}',
        text=True,
        capture_output=True,
        check=True,
    )
    if Path(result.stdout.strip()) != Path.cwd().resolve():
        raise SystemExit("Nautilus launcher did not resolve a terminal process cwd")

required_wiring = {
    "home/desktop/default.nix": ["./nautilus.nix"],
    "home/desktop/nautilus.nix": [
        "./nautilus-terminal-cwd.py",
        "systemd.user.services.udiskie",
    ],
    "home/desktop/packages.nix": [
        "alsa-utils",
        "brightnessctl",
        "ffmpegthumbnailer",
        "grim\n",
        "grimblast",
        "gvfs",
        "hyprlock",
        "nautilus",
        "playerctl",
        "slurp",
        "sushi",
        "udiskie",
        "wl-clipboard",
    ],
    "config/alacritty/alacritty.toml": [
        'key = "Insert", mods = "Control", action = "Copy"',
        'key = "Insert", mods = "Shift", action = "Paste"',
    ],
    "config/kitty/kitty.conf": [
        "map ctrl+insert            copy_to_clipboard",
        "map shift+insert           paste_from_clipboard",
    ],
}
for relative_path, fragments in required_wiring.items():
    content = (root / relative_path).read_text()
    for fragment in fragments:
        if fragment not in content:
            raise SystemExit(f"missing desktop wiring in {relative_path}: {fragment}")
