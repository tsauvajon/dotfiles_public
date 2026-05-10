# Starter template for ~/.config/dotfiles/flake.nix.
#
# `setup.sh` auto-copies this file into place on first run when
# ~/.config/dotfiles/flake.nix is missing. Edit the placeholders
# below, then rerun ./setup.sh to build and activate.
#
# This flake is consumed by the public dotfiles flake as
# `inputs.private`. Every field below is read by a Home Manager
# module under home/. Required vs. optional:
#
#   git.{name,email}             REQUIRED — used to generate machine keys.
#   git.signingKey               REQUIRED by the build, auto-filled by setup.
#   everything else              OPTIONAL — null/[]/omitted is fine.
#
# After editing this file, just rerun:
#
#   ./setup.sh
#
# `--override-input private "path:$HOME/.config/dotfiles"` is passed
# automatically, so you do NOT need to update flake.lock.
{
  description = "Private dotfiles overlay";

  outputs =
    { self, ... }:
    {
      # REQUIRED — git identity. Fill name/email, then rerun setup.sh.
      # When signingKey is empty, setup.sh generates or detects a GPG
      # key for this email and patches the key id into this file.
      #
      # First-run shortcut: instead of hand-editing this file, you can
      # seed all three fields by exporting DOTFILES_GIT_NAME and
      # DOTFILES_GIT_EMAIL before running setup.sh; the bootstrap
      # script patches the empty literals below in place.
      git = {
        name = ""; # e.g. "Your Full Name" (or set DOTFILES_GIT_NAME)
        email = ""; # e.g. "you@example.com" (or set DOTFILES_GIT_EMAIL)
        signingKey = ""; # auto-filled by scripts/bootstrap-keys.sh

        # Optional: extra gitconfig include for per-machine tweaks.
        # extraConfigInclude = ./extra.gitconfig;
      };

      # Optional — goto bookmarks (https://github.com/tsauvajon/goto).
      # Setting `apiUrl` enables the goto client config; clear it (or
      # set to null) to skip. On Darwin, the goto-api launchd agent
      # reads from `bookmarksFile`; create the file at the path below
      # to populate the database.
      goto = {
        apiUrl = "http://127.0.0.1:50002";
        bookmarksFile = ./goto/database.yml;
      };

      # Optional — personal-only applications and services. Keep the
      # top-level switch false on work machines; flipping it to true
      # enables the per-app toggles below.
      #
      # Per-app install paths:
      #   signal     pkgs.signal-desktop on both Linux and macOS.
      #   syncthing  HM service (systemd user / launchd agent).
      #   tailscale  Linux: pkgs.tailscale. macOS: Homebrew-managed cask.
      #   gurk       pkgs.gurk-rs on personal hosts only.
      #   naps2      Linux: pkgs.naps2. macOS: Homebrew-managed cask.
      personal = {
        enable = false;
        signal.enable = true;
        syncthing.enable = true;
        chromium.enable = true;
        gurk.enable = true;
        naps2.enable = true;
        tailscale.enable = true;
      };

      # Optional — OpenCode private overlays.
      #
      # Defaults: every overlay path falls back to the standard
      # subpath under `<this flake>/opencode/`. Just drop a file or
      # directory at one of these locations and it gets merged in:
      #
      #   ./opencode/commands/        slash commands
      #   ./opencode/skills/          loadable skills
      #   ./opencode/agents/          agent definitions
      #   ./opencode/plugins/         autoloaded plugins
      #   ./opencode/rules/           AGENTS.md fragments
      #   ./opencode/opencode.json    config overlay (e.g. MCP servers)
      #   ./opencode/package.json     plugin dependency overlay
      #
      # Override only when you need a non-standard layout. Use `null`
      # to disable an overlay even when the standard subpath exists,
      # or pass a custom Nix path to point elsewhere — e.g.:
      #
      #   opencode.commandsDir = ./alt-commands;
      #   opencode.skillsDir   = null;
      opencode = {
        # External non-Nix repos contributing skills, commands, plugins,
        # rules, and opencode.*.json fragments. setup.sh syncs each
        # source into ./opencode-imports/<name>/ before the build.
        #
        # Schema (see AGENTS.md > "External imports" for full details):
        #   { name    = "...";          # required, staging dir name
        #     source  = "~/path/to/repo";   # required, supports leading ~
        #
        #     # Auto mode (default): every entry under commands/, skills/,
        #     # agents/, plugins/, rules/, plus top-level opencode.*.json
        #     # and package.json, is staged automatically. These tweaks
        #     # apply to the auto walk:
        #     rename  = { "<src>" = "<dest>"; ... };
        #         # Renames an auto-discovered item; also imports
        #         # non-standard files (e.g. mcp.fragment.json).
        #     exclude = [ "<src>" ... ];
        #         # Skip these during the auto walk.
        #
        #     # Cherry-pick mode: when `paths` is set, auto walk is OFF
        #     # and only these mappings are imported. Mutually exclusive
        #     # with `rename` / `exclude`.
        #     paths   = { "<src>" = "<dest>"; ... };
        #   }
        imports = [ ];
      };

      # Optional — extra Home Manager modules contributed by this overlay.
      # Anything in this list is appended to the public flake's module
      # list and loaded into every host configuration.
      homeModules = [ ];
    };

  # Other private files this dotfiles tree understands (no Nix code
  # required to enable them — just drop a file at the listed path):
  #
  #   ~/.config/dotfiles/extra.gitconfig
  #     Included from ~/.config/git/config when git.extraConfigInclude
  #     points to it (see above).
  #
  #   ~/.config/dotfiles/ssh/config
  #     Private SSH hosts; included from ~/.ssh/config.
  #
  #   ~/.config/dotfiles/cargo.<name>.toml
  #     Cargo overlays, appended onto config/cargo/cargo-config.toml.
  #
  #   ~/.config/dotfiles/aerospace.<name>.toml
  #     AeroSpace rules, appended onto config/aerospace/aerospace.toml.
  #
  #   ~/.config/dotfiles/alacritty.<name>.toml
  #     Alacritty overlays, appended onto config/alacritty/alacritty.toml.
  #
  #   ~/.config/dotfiles/task.<name>.toml
  #     Task overlays, merged onto config/task/config.toml.
  #
  #   ~/.config/dotfiles/plist/<name>.plist
  #     Fallback macOS LaunchAgents loader: hand-authored XML plists
  #     here are symlinked into ~/Library/LaunchAgents/. Prefer typed
  #     `launchd.agents.<name>` in a Home Manager module for new
  #     agents; see `home/launchd-goto.nix` in the public dotfiles
  #     for the canonical example.
  #
  #   ~/.config/dotfiles/opencode/opencode.*.json
  #     OpenCode JSON fragments (deep-merged in filename order).
}
