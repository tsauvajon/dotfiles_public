#!/usr/bin/env sh

# Waybar fallback reload (the wired SUPER+SHIFT+R binding uses the
# generated ~/.config/hypr/status-bar script instead). Hyprbaric is
# stopped too so exactly one status bar runs after a reload.

# Terminate already running bar instances
killall -q waybar .waybar-wrapped hyprbaric

# Wait until the processes have been shut down (bounded)
attempts=0
while pgrep -x waybar >/dev/null || pgrep -x .waybar-wrapped >/dev/null || pgrep -x hyprbaric >/dev/null; do
    if [ "$attempts" -ge 30 ]; then
        echo "reload.sh: bar processes did not exit" >&2
        exit 1
    fi
    sleep 0.1
    attempts=$((attempts + 1))
done

# Waybar has no notification server; ensure mako is running.
if ! pgrep -x mako >/dev/null; then
    mako >/dev/null 2>&1 &
fi

# Launch main
waybar
