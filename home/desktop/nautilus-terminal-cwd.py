#!/usr/bin/env python3
"""Print a safe directory for Nautilus from a Hyprland active-window JSON object."""

import json
import os
import sys
from pathlib import Path


fallback = Path(os.environ.get("HOME", "/"))
try:
    window = json.load(sys.stdin)
except (json.JSONDecodeError, OSError):
    print(fallback)
    raise SystemExit
if not isinstance(window, dict):
    print(fallback)
    raise SystemExit

terminal_classes = {
    sys.argv[1].casefold(),
    "alacritty",
    "kitty",
    "foot",
    "terminal-yazi",
}
window_classes = {
    str(window.get("class", "")).casefold(),
    str(window.get("initialClass", "")).casefold(),
}
if not terminal_classes & window_classes:
    print(fallback)
    raise SystemExit

try:
    root_pid = int(window["pid"])
except (KeyError, TypeError, ValueError):
    print(fallback)
    raise SystemExit


def process_info(pid: int) -> tuple[Path, bool] | None:
    """Return (cwd, foreground) from proc, tolerating exited processes."""
    proc = Path("/proc") / str(pid)
    try:
        cwd = proc.joinpath("cwd").resolve(strict=True)
        # Fields after the parenthesized comm start at field 3 (state).
        fields = proc.joinpath("stat").read_text().rsplit(") ", 1)[1].split()
        pgrp, tty_nr, tpgid = map(int, (fields[2], fields[4], fields[5]))
        return cwd, tty_nr != 0 and pgrp == tpgid
    except (IndexError, OSError, ValueError):
        return None


# Prefer the deepest process in the terminal PTY foreground group. This avoids
# following an unrelated background child while still finding shells and Yazi.
candidates: list[tuple[bool, int, Path]] = []
pending = [(root_pid, 0)]
seen = set()
while pending:
    pid, depth = pending.pop()
    if pid in seen or depth > 32:
        continue
    seen.add(pid)
    info = process_info(pid)
    if info is not None and info[0].is_dir():
        candidates.append((info[1], depth, info[0]))
    try:
        children_files = list((Path("/proc") / str(pid) / "task").glob("*/children"))
    except OSError:
        children_files = []
    for children_file in children_files:
        try:
            children = children_file.read_text().split()
            pending.extend((int(child), depth + 1) for child in children)
        except (OSError, ValueError):
            pass

print(max(candidates, default=(False, -1, fallback), key=lambda item: item[:2])[2])
