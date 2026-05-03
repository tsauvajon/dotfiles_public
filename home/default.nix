{
  config,
  lib,
  pkgs,
  ...
}:

let
  dotfiles = ../.;
  cfg = path: dotfiles + "/config/${path}";
  readConfig = path: builtins.readFile (cfg path);

  fishConfig = readConfig "fish/config.fish";
  fishAliases = readConfig "fish/aliases.fish";
  fishConfD = lib.pipe (builtins.readDir (cfg "fish/conf.d")) [
    (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".fish" name))
    (lib.mapAttrsToList (name: _: readConfig "fish/conf.d/${name}"))
    (lib.concatStringsSep "\n\n")
  ];
  fishFunctions = lib.pipe (builtins.readDir (cfg "fish/functions")) [
    (lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".fish" name))
    (lib.mapAttrs' (
      name: _:
      lib.nameValuePair (lib.removeSuffix ".fish" name) {
        body = readConfig "fish/functions/${name}";
      }
    ))
  ];
in
{
  home.username = "thomas";
  home.homeDirectory = "/home/thomas";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  programs.fish = {
    enable = true;
    shellInit =
      lib.replaceStrings [ ''source "$HOME/.config/fish/aliases.fish"'' ] [ fishAliases ]
        fishConfig;
    interactiveShellInit = fishConfD;
    functions = fishFunctions;
  };

  programs.helix = {
    enable = true;
    settings = builtins.fromTOML (readConfig "helix/config.toml");
    languages = builtins.fromTOML (readConfig "helix/languages.toml");
  };

  programs.kitty = {
    enable = true;
    extraConfig = ''
      ${readConfig "kitty/colours.conf"}

      ${lib.replaceStrings [ "include colours.conf" ] [ "" ] (readConfig "kitty/kitty.conf")}
    '';
  };

  services.mako = {
    enable = true;
    settings = {
      anchor = "top-right";
      layer = "overlay";
      margin = 16;
      padding = 12;
      border-size = 2;
      border-radius = 8;
      max-visible = 6;
      default-timeout = 6000;
      ignore-timeout = 1;
      font = "JetBrainsMono Nerd Font 11";
    };
    extraConfig = ''
      [urgency=high]
      border-color=#f38ba8ff
      default-timeout=0
    '';
  };

  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    mouse = true;
    prefix = "C-b";
    plugins = with pkgs.tmuxPlugins; [
      resurrect
      continuum
      catppuccin
    ];
    extraConfig = ''
      set -g prefix2 IC
      set -g set-clipboard on
      set -g status-position top
      set -g detach-on-destroy off

      bind r source-file ~/.config/tmux/tmux.conf
      bind t new-window

      bind ] split-window -h
      bind '\' split-window -v

      unbind '"'
      unbind %
      bind '"' split-window -h
      bind % split-window -v

      bind -n WheelUpPane if-shell -F -t = "#{mouse_any_flag}" "send-keys -M" "if -Ft= '#{pane_in_mode}' 'send-keys -M' 'copy-mode -e; send-keys -M'"

      set -g @resurrect-capture-pane-contents 'on'
      set -g @resurrect-auto-restore 'on'
      set -g @continuum-restore 'on'

      set -g @catppuccin_flavor "mocha"
      set -g @catppuccin_window_status_style "basic"
      set -g @catppuccin_window_current_text " #{window_name}"
      set -g @catppuccin_window_text " #{window_name}"
      set -g @catppuccin_window_current_number_color "#{?window_zoomed_flag,#{@thm_yellow},#{@thm_mauve}}"
      set -g @catppuccin_window_number_color "#{?window_zoomed_flag,#{@thm_yellow},#{@thm_overlay_2}}"
    '';
  };

  programs.yazi = {
    enable = true;
    shellWrapperName = "yy";
    keymap = builtins.fromTOML (readConfig "yazi/keymap.toml");
    initLua = readConfig "yazi/init.lua";
  };

  programs.zellij = {
    enable = true;
    themes.catppuccin-mocha = ''
      themes {
        catppuccin-mocha {
          bg "#585b70"
          fg "#cdd6f4"
          red "#f38ba8"
          green "#a6e3a1"
          blue "#89b4fa"
          yellow "#f9e2af"
          magenta "#f5c2e7"
          orange "#fab387"
          cyan "#89dceb"
          black "#181825"
          white "#cdd6f4"
        }
      }
    '';
    extraConfig = readConfig "zellij/config.kdl";
  };
}
