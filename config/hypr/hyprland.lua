-- Hyprland 0.55+ configuration. See https://wiki.hypr.land/Configuring/Start/

------------------
---- MONITORS ----
------------------

hl.monitor({
    output = "DP-2",
    mode = "5120x2160@120",
    position = "auto",
    scale = 1,
})

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    hl.exec_cmd("waybar &")
    hl.exec_cmd("mako &")
    hl.exec_cmd("~/.nix-profile/bin/terminal-launcher --class ssh-add -- ssh-add ~/.ssh/id_ed25519")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- Keep overlapping NVIDIA/Wayland values deliberately in sync with
-- config/wayland-env.sh, which is sourced from ~/.profile before the compositor.
-- https://wiki.hypr.land/0.41.2/Nvidia
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("EGL_PLATFORM", "wayland")
hl.env("WLR_NO_HARDWARE_CURSORS", "1")

-- Mouse cursor themes through hyprcursor.
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("HYPRCURSOR_SIZE", "42")
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "42")

-- Nvidia VA-API (?) hardware video acceleration.
hl.env("NVD_BACKEND", "direct")

-- Force Mozilla to use Wayland.
hl.env("MOZ_ENABLE_WAYLAND", "1")

-- Qt.
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")

-- Fixes Electron/CEF flickering.
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")

-- SSH agent (managed by systemd user socket).
hl.env("SSH_AUTH_SOCK", "/run/user/1000/ssh-agent.socket")

-------------------
---- LOOK & FEEL ---
-------------------

hl.config({
    general = {
        col = {
            active_border = { colors = { "rgba(f38ba8ff)", "rgba(74c7ecff)" }, angle = 45 },
            inactive_border = "rgba(50536aff)",
        },
        gaps_in = 5,
        gaps_out = { top = 0, right = 10, bottom = 0, left = 10 },
        border_size = 2,
        layout = "dwindle",
        allow_tearing = true, -- ChatGPT suggested this for better framerate.
        resize_on_border = true, -- Resize with the mouse.
        extend_border_grab_area = 10,
        hover_icon_on_border = true,
    },

    input = {
        kb_layout = "us",
        kb_variant = "altgr-intl",
        follow_mouse = 2, -- Clicking on a window focuses the keyboard on it.
        natural_scroll = true, -- macOS style.
    },

    cursor = {
        no_hardware_cursors = true, -- NVIDIA sometimes fails to show the cursor.
        no_warps = true,
        enable_hyprcursor = true,
        default_monitor = "DP-2",
    },

    decoration = {
        rounding = 10,
        active_opacity = 1.0,
        fullscreen_opacity = 1.0,
        inactive_opacity = 0.95,
        blur = {
            enabled = true,
            size = 4,
            passes = 3,
            new_optimizations = true,
        },
        shadow = {
            enabled = true,
            offset = { 5, 5 },
            range = 25,
            render_power = 4,
            color = "rgba(18192688)",
            color_inactive = "rgba(00000088)",
        },
    },

    animations = { enabled = true },

    misc = {
        render_unfocused_fps = 60,
        disable_hyprland_logo = true, -- Anime girl in the background.
        force_default_wallpaper = 0, -- Anime girl wallpaper.
        disable_splash_rendering = true,
        vrr = 2, -- Adaptive sync when in games.
        focus_on_activate = true, -- Focus newly opened windows.
        mouse_move_focuses_monitor = true,
    },

    debug = {
        vfr = false, -- Long-unfocused windows can otherwise become very laggy (e.g. WoW).
    },

    dwindle = { preserve_split = true },
    xwayland = { force_zero_scaling = true }, -- Fixes VS Code.

})

-- hyprwinwrap registers its configuration keys when the plugin is loaded.
-- Keeping this conditional lets Hyprland start cleanly before hyprpm loads it.
if hl.plugin.hyprwinwrap ~= nil then
    hl.plugin.hyprwinwrap.window({ class = "kitty-bg" })
end

hl.curve("wind", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.0 } } })
hl.curve("winIn", { type = "bezier", points = { { 0.1, 1.0 }, { 0.1, 1.0 } } })
hl.curve("winOut", { type = "bezier", points = { { 0.3, -0.3 }, { 0, 1 } } })
hl.curve("liner", { type = "bezier", points = { { 1, 1 }, { 1, 1 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 6, bezier = "wind", style = "slide" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 6, bezier = "winIn", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "winOut", style = "slide" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 5, bezier = "wind", style = "slide" })
hl.animation({ leaf = "border", enabled = true, speed = 1, bezier = "liner" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 30, bezier = "liner", style = "loop" })
hl.animation({ leaf = "fade", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "wind" })

---------------------
---- KEYBINDINGS ----
---------------------

local terminal = "~/.nix-profile/bin/terminal-launcher"
local fallbackTerminal = "~/.nix-profile/bin/safe-terminal"
local browser = "firefox"
local compatibleBrowser = "chromium"
local notes = "obsidian"
local fileManager = "~/.nix-profile/bin/terminal-launcher --class terminal-yazi --hold -- yazi"
local passwordManager = "keepassxc"
local screenshot = "grim -g \"$(slurp)\" - | swappy -f -"
local menu = "rofi -show drun"
local procViewer = "~/.nix-profile/bin/terminal-launcher --hold -- htop"
local reloadBar = "~/.config/waybar/scripts/reload.sh"

hl.bind("SUPER + Q", hl.dsp.exit())

-- Switch workspaces with SUPER + [0-9].
for workspace = 1, 9 do
    hl.bind("SUPER + " .. workspace, hl.dsp.focus({ workspace = workspace }))
end
hl.bind("SUPER + G", hl.dsp.focus({ workspace = 10 }))
hl.bind("SUPER + TAB", hl.dsp.focus({ workspace = "previous" }))

-- Scroll through existing workspaces with SUPER + scroll.
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move active window to a workspace with SUPER + SHIFT + [0-9].
for workspace = 1, 8 do
    hl.bind("SUPER + SHIFT + " .. workspace, hl.dsp.window.move({ workspace = workspace }))
end
hl.bind("SUPER + SHIFT + O", hl.dsp.window.move({ workspace = 9 }))
hl.bind("SUPER + SHIFT + G", hl.dsp.window.move({ workspace = 10 }))

-- Resize the active window with CTRL + SHIFT + arrow keys.
hl.bind("CTRL + SHIFT + left", hl.dsp.window.resize({ x = -200, y = 0, relative = true }))
hl.bind("CTRL + SHIFT + right", hl.dsp.window.resize({ x = 200, y = 0, relative = true }))
hl.bind("CTRL + SHIFT + up", hl.dsp.window.resize({ x = 0, y = -200, relative = true }))
hl.bind("CTRL + SHIFT + down", hl.dsp.window.resize({ x = 0, y = 200, relative = true }))

-- Move windows and focus with vim keys or arrow keys.
for _, bind in ipairs({
    { "H", "left" }, { "left", "left" }, { "L", "right" }, { "right", "right" },
    { "J", "down" }, { "down", "down" }, { "K", "up" }, { "up", "up" },
}) do
    hl.bind("SUPER + CTRL + " .. bind[1], hl.dsp.window.move({ direction = bind[2] }))
end
hl.bind("SUPER + H", hl.dsp.focus({ direction = "left" }))
hl.bind("SUPER + L", hl.dsp.focus({ direction = "right" }))
hl.bind("SUPER + J", hl.dsp.focus({ direction = "down" }))
hl.bind("SUPER + K", hl.dsp.focus({ direction = "up" }))

-- Move/resize windows with SUPER + LMB/RMB and dragging.
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Tip for registering function keys: keycodes can be checked with "wev".
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl --device='amdgpu_bl1' set +10%"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl --device='amdgpu_bl1' set 10%-"), { locked = true, repeating = true })
hl.bind("code:237", hl.dsp.exec_cmd("asusctl -p"), { locked = true, repeating = true })
hl.bind("code:238", hl.dsp.exec_cmd("asusctl -n"), { locked = true, repeating = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("amixer set Master 2%-"), { locked = true, repeating = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("amixer set Master 2%+"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("amixer set Master toggle"), { locked = true, repeating = true })

hl.bind("SUPER + return", hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + SHIFT + return", hl.dsp.exec_cmd(fallbackTerminal))
hl.bind("SUPER + W", hl.dsp.exec_cmd(fileManager))
hl.bind("SUPER + X", hl.dsp.exec_cmd(passwordManager))
hl.bind("SUPER + B", hl.dsp.exec_cmd(browser))
hl.bind("SUPER + Z", hl.dsp.exec_cmd(compatibleBrowser))
hl.bind("SUPER + O", hl.dsp.exec_cmd(notes))
hl.bind("ALT + SHIFT + 4", hl.dsp.exec_cmd(screenshot))
hl.bind("SUPER + DELETE", hl.dsp.exec_cmd(procViewer))
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd(reloadBar))

hl.bind("SUPER + F", hl.dsp.window.fullscreen())
hl.bind("SUPER + V", hl.dsp.window.float())
hl.bind("SUPER + P", hl.dsp.window.pseudo()) -- Dwindle.

-- Both SUPER + SPACE and F4 open the app launcher.
hl.bind("ALT + space", hl.dsp.exec_cmd(menu))
hl.bind("code:212", hl.dsp.exec_cmd(menu))
hl.bind("SUPER + space", hl.dsp.exec_cmd(menu))

-- Both ALT + Q and ALT + F4 close windows.
hl.bind("ALT + Q", hl.dsp.window.close())
hl.bind("ALT + code:212", hl.dsp.window.close())

-- Pyprland center layout keybinds.
-- https://hyprland-community.github.io/pyprland/layout_center.html
hl.bind("SUPER + O", hl.dsp.exec_cmd("pypr layout_center toggle"))
hl.bind("SUPER + left", hl.dsp.exec_cmd("pypr layout_center prev")) -- Falls back to movefocus left.
hl.bind("SUPER + right", hl.dsp.exec_cmd("pypr layout_center next")) -- Falls back to movefocus right.
hl.bind("SUPER + up", hl.dsp.exec_cmd("pypr layout_center prev2")) -- Falls back to movefocus up.
hl.bind("SUPER + down", hl.dsp.exec_cmd("pypr layout_center next2")) -- Falls back to movefocus down.

-- Dell U4025QW input switching via DDC/CI. Requires i2c-dev and i2c group access.
hl.bind("CTRL + ALT + 1", hl.dsp.exec_cmd("~/.nix-profile/bin/monitor-input thunderbolt"))
hl.bind("CTRL + ALT + 2", hl.dsp.exec_cmd("~/.nix-profile/bin/monitor-input dp"))
hl.bind("CTRL + ALT + 3", hl.dsp.exec_cmd("~/.nix-profile/bin/monitor-input hdmi"))

----------------------------
---- WINDOW AND LAYER RULES -
----------------------------

-- Rules are evaluated top to bottom; preserve their legacy order.
hl.window_rule({ match = { title = "^(Save File)$" }, float = true })
hl.window_rule({ match = { title = "^(Open File)$" }, float = true })
hl.window_rule({ match = { title = "^(Select Folder)$" }, float = true })
hl.window_rule({ match = { title = "^(Sign In - Google Accounts)$" }, float = true })
hl.window_rule({ match = { class = "^()$", title = "^(Save File)$" }, float = true })
hl.window_rule({ match = { class = "^()$", title = "^(Open File)$" }, float = true })
hl.window_rule({ match = { class = "^()$", title = "^(Select Folder)$" }, float = true })
hl.window_rule({ match = { class = "^(CachyOSHello)$" }, float = true })

for _, class in ipairs({
    "^(qalculate-gtk)$", "^(waypaper)$", "^(nm-connection-editor)$", "^(blueman-manager)$",
    "^(org.pulseaudio.pavucontrol)$", "^(jamesdsp)$", "^(org.kde.polkit-kde-authentication-agent-1)$",
    "^(.*desktop-portal-gtk.*)$", "^(xdg-desktop-portal-kde)$", "^(xdg-desktop-portal-hyprland)$",
    "^(com.github.Aylur.ags)$",
}) do
    hl.window_rule({ match = { class = class }, float = true })
end

-- File manager.
hl.window_rule({ match = { class = "^(pcmanfm)$" }, float = true })
hl.window_rule({ match = { class = "^(pcmanfm)$", initial_title = "^(Creating.*)$" }, size = { 450, 172 } })
hl.window_rule({ match = { class = "^(pcmanfm)$", initial_title = "^(Rename File)$" }, size = { 450, 172 } })
hl.window_rule({ match = { class = "^(pcmanfm)$", initial_title = "^(Execute File)$" }, size = { 600, 112 } })
hl.window_rule({ match = { class = "^(pcmanfm)$", initial_title = "^(Moving files)$" }, size = { 600, 242 } })
hl.window_rule({ match = { class = "^(pcmanfm)$" }, size = { 750, 500 } })

hl.window_rule({ match = { class = "^(feh)$" }, float = true })

-- GTK and Qt settings.
for _, class in ipairs({ "^(nwg-look)$", "^(dconf-editor)$", "^(qt5ct)$", "^(qt6ct)$", "^(kvantummanager)$" }) do
    hl.window_rule({ match = { class = class }, float = true })
end
hl.window_rule({ match = { class = "^(dconf-editor)$" }, size = { 500, 700 } })
hl.window_rule({ match = { class = "^(qt5ct)$" }, size = { 633, 600 } })
hl.window_rule({ match = { class = "^(qt6ct)$" }, size = { 658, 763 } })
hl.window_rule({ match = { class = "^(kvantummanager)$" }, size = { 753, 730 } })

for _, title in ipairs({ "^(Picture in picture)$", "^(Picture-in-Picture)$" }) do
    hl.window_rule({ match = { title = title }, float = true })
    hl.window_rule({ match = { title = title }, size = { 854, 480 } })
end

hl.window_rule({ match = { title = "(ROG Control)" }, float = true })
hl.window_rule({ match = { title = "(ROG Control)" }, size = { 900, 650 } })
hl.window_rule({ match = { title = "(ROG Control)" }, center = true })

hl.window_rule({ match = { class = "^(ssh-add)$" }, float = true })
hl.window_rule({ match = { class = "^(ssh-add)$" }, size = { 500, 200 } })
hl.window_rule({ match = { class = "^(ssh-add)$" }, center = true })

-- Selected terminal. Home Manager replaces the class placeholder.
hl.window_rule({ match = { class = "^(@defaultTerminalClass@)$" }, size = { 8200, 540 } })
hl.window_rule({ match = { class = "^(@defaultTerminalClass@)$" }, min_size = { 800, 500 } })

-- JetBrains IDEs.
for _, class in ipairs({ "^(jetbrains-idea-ce)$", "^(jetbrains-pycharm-ce)$", "^(jetbrains-rider)$", "^(jetbrains-webstorm)$" }) do
    hl.window_rule({ match = { class = class, title = "^(Remove Recent Project)$" }, center = true })
end

hl.window_rule({ match = { class = "^(zen-alpha)$" }, opaque = true })
hl.window_rule({ match = { class = "^(firefox)$" }, opaque = true })
hl.window_rule({ match = { class = "^(chromium)$" }, opaque = true })
hl.window_rule({ match = { class = "^(chromium)$", fullscreen = true }, border_size = 0 })
hl.window_rule({ match = { class = "^(chromium)$", fullscreen = true }, rounding = 0 })

for _, title in ipairs({ "^(New Download)$", "^(Download Complete)$", "^(0% .*)$" }) do
    hl.window_rule({ match = { class = "^(xdm-app)$", initial_title = title }, float = true })
end
hl.window_rule({ match = { class = "^(xdm-app)$", initial_title = "^(New Download)$" }, size = { 600, 230 } })
hl.window_rule({ match = { class = "^(xdm-app)$", initial_title = "^(Download Complete)$" }, size = { 450, 160 } })
hl.window_rule({ match = { class = "^(xdm-app)$", initial_title = "^(0% .*)$" }, size = { 500, 200 } })

hl.window_rule({ match = { class = "^(Spotify)$" }, monitor = "eDP-2" })
hl.window_rule({ match = { class = "^(mpv)$" }, float = true })
hl.window_rule({ match = { class = "^(mpv)$" }, size = { "70%", "70%" } })

-- Steam.
hl.window_rule({ match = { class = "(steam)" }, float = true })
hl.window_rule({ match = { class = "^()$", title = "^(Steam - Self Updater)$" }, float = true })
hl.window_rule({ match = { class = "^(steam)$", title = "^(Friends List)$" }, size = { 400, 600 } })
hl.window_rule({ match = { class = "^(steam)$", title = "^(Friends List)$" }, move = { "100%-w-30", "100%-w-75" } })
hl.window_rule({ match = { class = "(steam)", title = "^(.*Steam.*)$" }, tile = true })
hl.window_rule({ match = { class = "^(.*steam_app.*)$" }, size = { "80%", "80%" } })
hl.window_rule({ match = { class = "^(.*steam_app.*)$" }, fullscreen = true })
hl.window_rule({ match = { title = "^()$", class = "^(steam)$" }, min_size = { 1, 1 } })

local ryujinxOverlay = { class = "^(Ryujinx)$", title = "^(ContentDialogOverlayWindow)$" }
hl.window_rule({ match = ryujinxOverlay, fullscreen = true })
hl.window_rule({ match = ryujinxOverlay, stay_focused = true })
hl.window_rule({ match = ryujinxOverlay, opaque = true })
hl.window_rule({ match = ryujinxOverlay, border_size = 0 })
hl.window_rule({ match = ryujinxOverlay, no_shadow = true })
hl.window_rule({ match = ryujinxOverlay, no_anim = true })

for _, title in ipairs({ "^(Project Manager)$", "^(Preferences)$" }) do
    hl.window_rule({ match = { class = "^(resolve)$", title = title }, center = true })
end

hl.window_rule({ match = { class = "^(photoshop.exe)$" }, monitor = "HDMI-A-1" })
hl.window_rule({ match = { class = "^(photoshop.exe)$" }, tile = true })
hl.window_rule({ match = { class = "^(photo.exe)$" }, monitor = "HDMI-A-1" })
hl.window_rule({ match = { class = "^(photo.exe)$", initial_title = "^(Affinity Photo 2)$" }, tile = true })
hl.window_rule({ match = { class = "^(designer.exe)$" }, monitor = "HDMI-A-1" })
hl.window_rule({ match = { class = "^(designer.exe)$", initial_title = "^(Affinity Designer 2)$" }, tile = true })
hl.window_rule({ match = { class = "^(publisher.exe)$" }, monitor = "HDMI-A-1" })
hl.window_rule({ match = { class = "^(publisher.exe)$", initial_title = "^(Affinity Publisher 2)$" }, tile = true })

local shotcut = { class = "^(org.shotcut.Shotcut)$", initial_title = "^(Shotcut)$" }
hl.window_rule({ match = shotcut, float = true })
hl.window_rule({ match = shotcut, size = { 320, 320 } })
hl.window_rule({ match = shotcut, center = true })

local telegramMedia = { class = "^(org.telegram.desktop)$", title = "^(Media viewer)$" }
hl.window_rule({ match = telegramMedia, size = { "70%", "60%" } })
hl.window_rule({ match = telegramMedia, float = true })

-- WoW windows stay rendered while unfocused.
hl.window_rule({ match = { class = "^(wow.exe)$" }, tag = "+unfocused" })
hl.window_rule({ match = { tag = "unfocused" }, render_unfocused = true })

-- Ignore XWayland Video Bridge.
hl.window_rule({ match = { class = "^(xwaylandvideobridge)$" }, opacity = "0.0 override 0.0 override" })
hl.window_rule({ match = { class = "^(xwaylandvideobridge)$" }, no_anim = true })
hl.window_rule({ match = { class = "^(xwaylandvideobridge)$" }, no_focus = true })
hl.window_rule({ match = { class = "^(xwaylandvideobridge)$" }, no_initial_focus = true })

-- Forbid apps from maximizing or fullscreening themselves.
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })
hl.window_rule({ match = { class = ".*" }, suppress_event = "fullscreen" })

-- Idle inhibit.
hl.window_rule({ match = { title = ".*(yuzu).*" }, idle_inhibit = "focus" })
hl.window_rule({ match = { class = ".*(steam_app).*" }, idle_inhibit = "focus" })
hl.window_rule({ match = { class = "^(zen-alpha)$", title = "^(.*YouTube.*)$" }, idle_inhibit = "always" })
hl.window_rule({ match = { class = "^(zen-alpha)$", title = "^(.*S[0-9].*E[0-9].*)$" }, idle_inhibit = "always" })
