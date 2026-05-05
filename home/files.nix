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

let
  catppuccinMocha =
    (builtins.fromJSON (
      builtins.readFile "${
        inputs.catppuccin.packages.${pkgs.stdenv.hostPlatform.system}.palette
      }/palette.json"
    )).mocha.colors;

  catppuccin = color: catppuccinMocha.${color}.hex;
  style = attrs: attrs;
  boldStyle = attrs: attrs // { add_modifier = "BOLD"; };
  withBaseBackground = fg: {
    bg = catppuccin "base";
    inherit fg;
  };
  withCrustForeground = bg: {
    inherit bg;
    fg = catppuccin "crust";
  };

  accentColors = map catppuccin [
    "blue"
    "green"
    "yellow"
    "red"
    "pink"
    "teal"
  ];

  tabiewCatppuccinMochaTheme = {
    table_header = style {
      bg = catppuccin "base";
      fg = catppuccin "text";
    };

    table_headers = map (color: boldStyle (withBaseBackground color)) accentColors;

    rows = [
      (style {
        bg = catppuccin "surface0";
        fg = catppuccin "text";
      })
      (style {
        bg = catppuccin "surface1";
        fg = catppuccin "text";
      })
    ];

    row_highlight = style {
      bg = catppuccin "rosewater";
      fg = catppuccin "text";
    };

    table_tags = map (color: boldStyle (withCrustForeground color)) accentColors;

    block = style {
      bg = catppuccin "base";
      fg = catppuccin "blue";
    };
    block_tag = boldStyle {
      bg = catppuccin "blue";
      fg = catppuccin "crust";
    };
    text = style {
      bg = catppuccin "base";
      fg = catppuccin "text";
    };
    text_highlighted = boldStyle {
      bg = catppuccin "base";
      fg = catppuccin "blue";
    };
    subtext = style {
      bg = catppuccin "base";
      fg = catppuccin "overlay0";
    };
    error = boldStyle {
      bg = catppuccin "red";
      fg = catppuccin "crust";
    };
    gutter = style {
      bg = catppuccin "surface0";
      fg = catppuccin "overlay0";
    };

    chart = map (color: boldStyle (withBaseBackground color)) accentColors;
  };

  tabiewReadableSelection = {
    row_highlight = boldStyle {
      bg = catppuccin "blue";
      fg = catppuccin "crust";
    };
  };

  tabiewTheme = (pkgs.formats.toml { }).generate "tabiew-theme.toml" (
    tabiewCatppuccinMochaTheme // tabiewReadableSelection
  );
in

{
  # Files at $HOME (not under .config).
  home.file = {
    ".profile".source = ../config/shell/profile;
    ".bashrc".source = ../config/shell/bashrc;
    ".bash_profile".source = ../config/shell/bash_profile;
    ".fish_profile".source = ../config/shell/fish_profile;
    ".zshrc".source = ../config/shell/zshrc;
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
      # `recursive = true` lets other modules add per-file entries
      # under fish/ (e.g. xdg.configFile."fish/conf.d/common-aliases.fish"
      # from cross-shell-aliases.nix, or "fish/completions/task.fish"
      # from task.nix). Without it, HM tries to symlink the whole dir
      # at once and conflicts with later per-file entries.
      "fish" = {
        source = ../config/fish;
        recursive = true;
      };
      "helix".source = ../config/helix;
      "bat".source = ../config/bat;
      "tabiew/config.toml".source = ../config/tabiew/config.toml;
      "tabiew/theme.toml".source = tabiewTheme;
      # yazi: wire each config file individually so theme.toml and the
      # syntect tmTheme can come from upstream catppuccin flakes rather
      # than the broken in-tree symlinks left behind by phase 8.
      "yazi/yazi.toml".source = ../config/yazi/yazi.toml;
      "yazi/keymap.toml".source = ../config/yazi/keymap.toml;
      "yazi/init.lua".source = ../config/yazi/init.lua;
      "yazi/theme.toml".source = "${inputs.catppuccin-yazi}/themes/mocha/catppuccin-mocha-blue.toml";
      "yazi/Catppuccin-mocha.tmTheme".source = "${inputs.catppuccin-bat}/themes/Catppuccin Mocha.tmTheme";
      "zellij/config.kdl".source = ../config/zellij/config.kdl;
      "kitty".source = ../config/kitty;
      "espflash".source = ../config/espflash;
      "obsidian/Preferences" = {
        source = ../config/obsidian/Preferences;
        force = true;
      };
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
