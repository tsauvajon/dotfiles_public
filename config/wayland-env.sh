# Pre-compositor login environment sourced from ~/.profile.
# Keep overlapping NVIDIA/Wayland values deliberately in sync with
# config/hypr/env.conf, which sets the Hyprland session environment.
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export LIBVA_DRIVER_NAME=nvidia
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export WLR_NO_HARDWARE_CURSORS=1
