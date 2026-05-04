# Tmux configuration via Home Manager.
#
# Replaces:
# - The git submodule plugins under config/tmux/plugins/{tpm,
#   tmux-resurrect, tmux-continuum, tmux (catppuccin)}.
# - The Rust setup tool's symlinks for ~/.tmux.conf and
#   ~/.tmux/plugins.
#
# Plugin extraConfig is rendered BEFORE the plugin loads; the
# top-level extraConfig is rendered AFTER, which matters for
# catppuccin variables (set before) versus status-line uses
# of @catppuccin_status_* substitutions (consumed after).
{ pkgs, ... }:

{
  programs.tmux = {
    enable = true;

    plugins = [
      pkgs.tmuxPlugins.resurrect
      pkgs.tmuxPlugins.continuum
      {
        plugin = pkgs.tmuxPlugins.catppuccin;
        extraConfig = ''
          set -g @catppuccin_flavor "mocha"
          set -g @catppuccin_window_status_style "basic"
          set -g @catppuccin_window_current_text " #{window_name}"
          set -g @catppuccin_window_text " #{window_name}"
          # typos: ignore
          set -g @catppuccin_window_current_number_color "#{?window_zoomed_flag,#{@thm_yellow},#{@thm_mauve}}"
          # typos: ignore
          set -g @catppuccin_window_number_color "#{?window_zoomed_flag,#{@thm_yellow},#{@thm_overlay_2}}"
        '';
      }
    ];

    extraConfig = ''
      set-option -g default-terminal "tmux-256color"

      set -g mouse on
      set -g prefix2 IC

      set -g set-clipboard on          # use system clipboard
      set -g status-position top       # macOS / darwin style
      set -g detach-on-destroy off     # don't exit from tmux when closing a session

      bind r source-file ~/.tmux.conf
      bind t new-window

      bind ] split-window -h
      bind '\' split-window -v

      # Invert default split bindings: " for horizontal, % for vertical
      unbind '"'
      unbind %
      bind '"' split-window -h
      bind % split-window -v

      # 'Sane' mouse scrolling
      bind -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" "send-keys -M" "if -Ft= '#{pane_in_mode}' 'send-keys -M' 'copy-mode -e; send-keys -M'"

      # Persist tmux sessions and content
      set -g @resurrect-capture-pane-contents 'on'
      set -g @resurrect-auto-restore 'on'

      # Autosave/autoload by session name
      set -g @continuum-restore 'on'

      # Status line — render catppuccin modules (must come after the plugin loads)
      set -g status-left-length 100
      set -g status-right-length 100
      set -g status-left ""
      set -g status-right "#{E:@catppuccin_status_application}"
      set -agF status-right "#{E:@catppuccin_status_session}"
      set -agF status-right "#{E:@catppuccin_status_uptime}"
    '';
  };
}
