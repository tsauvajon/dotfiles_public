# Plain-symlink dotfiles owned by Home Manager.
#
# Most tools just need their config directory or single file present
# at the canonical $HOME / $XDG_CONFIG_HOME path. This module wires
# all of them in one place so the Rust setup tool no longer has to.
# Tools that benefit from a richer HM integration (programs.tmux,
# programs.git, programs.opencode etc.) live in their own modules.
{
  pkgs,
  lib,
  inputs,
  ...
}:

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
      "yazi".source = ../config/yazi;
      "zellij/config.kdl".source = ../config/zellij/config.kdl;
      "kitty".source = ../config/kitty;
      "espflash".source = ../config/espflash;
      "obsidian/Preferences".source = ../config/obsidian/Preferences;
      "keepassxc/keepassxc.ini".source = ../config/keepassxc/keepassxc.ini;

      # Catppuccin themes pulled from upstream flake inputs (Phase 8)
      # rather than git submodules. Paths preserve the layout the
      # consumers expect:
      #   ~/.config/fzf/catppuccin/themes/catppuccin-fzf-mocha.fish
      #     — sourced by config/fish/config.fish
      #   ~/.config/zellij/themes/catppuccin.kdl
      #     — picked up by zellij's themes auto-discovery
      "fzf/catppuccin".source = inputs.catppuccin-fzf;
      "zellij/themes/catppuccin.kdl".source = "${inputs.catppuccin-zellij}/catppuccin.kdl";
    }

    # Linux-only: the wayland session env script, sourced by the
    # window manager.
    (lib.mkIf pkgs.stdenv.isLinux {
      "wayland-env.sh".source = ../config/wayland-env.sh;
    })
  ];
}
