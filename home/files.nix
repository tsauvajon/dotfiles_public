# Plain-symlink dotfiles owned by Home Manager.
#
# Most tools just need their config directory or single file present
# at the canonical $HOME / $XDG_CONFIG_HOME path. This module wires
# all of them in one place so the Rust setup tool no longer has to.
# Tools that benefit from a richer HM integration (programs.tmux,
# programs.git, programs.opencode etc.) live in their own modules.
{ pkgs, lib, ... }:

{
  # Files at $HOME (not under .config).
  home.file = {
    ".profile".source = ../config/shell/profile;
    ".bashrc".source = ../config/shell/bashrc;
    ".bash_profile".source = ../config/shell/bash_profile;
    ".fish_profile".source = ../config/shell/fish_profile;
    ".tool-versions".source = ../config/asdf/tool-versions;
    ".nix-channels".source = ../config/nix/nix-channels;
    # SSH config — public file lives in repo and pulls in the optional
    # private overlay at ~/.config/dotfiles/ssh/config via its top-line
    # `Include` directive. Keep this as a plain symlink so the include
    # path resolves to the live private file.
    ".ssh/config".source = ../config/ssh/config;
  };

  # Per-tool $XDG_CONFIG_HOME entries. Cross-platform unless gated.
  xdg.configFile = lib.mkMerge [
    {
      "fish".source = ../config/fish;
      "helix".source = ../config/helix;
      "bat".source = ../config/bat;
      "fzf".source = ../config/fzf;
      "eza".source = ../config/eza;
      "yazi".source = ../config/yazi;
      "zellij/config.kdl".source = ../config/zellij/config.kdl;
      "zellij/themes/catppuccin.kdl".source = ../config/zellij/catppuccin/catppuccin.kdl;
      "kitty".source = ../config/kitty;
      "espflash".source = ../config/espflash;
      "obsidian/Preferences".source = ../config/obsidian/Preferences;
      "keepassxc/keepassxc.ini".source = ../config/keepassxc/keepassxc.ini;
    }

    # Linux-only: the wayland session env script, sourced by the
    # window manager.
    (lib.mkIf pkgs.stdenv.isLinux {
      "wayland-env.sh".source = ../config/wayland-env.sh;
    })
  ];
}
