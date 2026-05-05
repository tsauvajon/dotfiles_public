# Format man pages
set -gx EDITOR hx
set -gx VISUAL hx
set -x MANROFFOPT -c
set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"
set -x BAT_THEME "Catppuccin Mocha"
# Source fzf catppuccin mocha theme from submodule
test -f ~/.config/fzf/catppuccin/themes/catppuccin-fzf-mocha.fish && source ~/.config/fzf/catppuccin/themes/catppuccin-fzf-mocha.fish

# Enable Wayland support for different applications
if [ "$XDG_SESSION_TYPE" = wayland ]
    set -gx WAYLAND 1
    set -gx QT_QPA_PLATFORM 'wayland;xcb'
    set -gx GDK_BACKEND 'wayland,x11'
    set -gx MOZ_DBUS_REMOTE 1
    set -gx MOZ_ENABLE_WAYLAND 1
    set -gx _JAVA_AWT_WM_NONREPARENTING 1
    set -gx BEMENU_BACKEND wayland
    set -gx CLUTTER_BACKEND wayland
    set -gx ECORE_EVAS_ENGINE wayland_egl
    set -gx ELM_ENGINE wayland_egl
end

# Override config for done.fish
set -U __done_min_cmd_duration 10000
set -U __done_notification_urgency_level low

# Apply .profile
if test -f ~/.fish_profile
    source ~/.fish_profile
end

# Add ~/.local/bin to PATH
if test -d ~/.local/bin
    if not contains -- ~/.local/bin $PATH
        set -p PATH ~/.local/bin
    end
end

if not set -q DEV_ROOT
    set -gx DEV_ROOT "$HOME/dev"
end

if test "$TERM" = xterm-kitty
    if test -d /usr/lib/kitty/terminfo
        set -gx TERMINFO /usr/lib/kitty/terminfo
    end
end

if type -q direnv
    direnv hook fish | source
end

if test -d ~/.cargo/bin
    if not contains -- ~/.cargo/bin $PATH
        set -p PATH ~/.cargo/bin
    end
end

## Run fastfetch at start
function fish_greeting
    fastfetch
end

# Aliases
source "$HOME/.config/fish/aliases.fish"

# Zoxide
zoxide init fish | source

# Spicetify
fish_add_path ~/.spicetify

# Go
set --export GOPATH "$HOME/go"
set --export PATH $GOPATH/bin $PATH
