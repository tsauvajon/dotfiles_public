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
#   git.{name,email,signingKey}  REQUIRED — build throws if empty.
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
      # REQUIRED — git identity. The build throws if any field is empty,
      # so leaving the placeholders here means setup.sh will refuse to
      # build until you fill them in.
      #
      # No GPG key yet? Generate one without installing anything globally:
      #   nix run nixpkgs#gnupg -- --quick-generate-key \
      #     "Your Name <you@example.com>" ed25519 default 1y
      #   nix run nixpkgs#gnupg -- --list-secret-keys --keyid-format long
      # Use rsa4096 instead of ed25519 for broader legacy compatibility.
      git = {
        name = ""; # TODO: e.g. "Your Full Name"
        email = ""; # TODO: e.g. "you@example.com"
        signingKey = ""; # TODO: 16-char hex after `sec ed25519/...`

        # Optional: extra gitconfig include for per-machine tweaks.
        # extraConfigInclude = ./extra.gitconfig;
      };

      # Optional — goto bookmarks (https://github.com/tsauvajon/goto).
      # Set apiUrl to enable; leave null to skip.
      goto = {
        apiUrl = null; # e.g. "http://127.0.0.1:50002"
        bookmarksFile = null; # e.g. ./goto/database.yml
      };

      # Optional — OpenCode private overlays. Each path is independently
      # optional; null/omitted skips that overlay. Files referenced by
      # configFile / packageFile may not exist — missing files are
      # treated as empty objects and merged accordingly.
      opencode = {
        commandsDir = null; # e.g. ./opencode/commands
        skillsDir = null; # e.g. ./opencode/skills
        agentsDir = null; # e.g. ./opencode/agents
        pluginsDir = null; # e.g. ./opencode/plugins
        rulesDir = null; # e.g. ./opencode/rules
        configFile = null; # e.g. ./opencode/opencode.json
        packageFile = null; # e.g. ./opencode/package.json

        # External non-Nix repos contributing skills/commands/etc.
        # See AGENTS.md > "External imports" for the schema.
        imports = [ ];

        # Populated by setup.sh's pre-build sync from `imports` above.
        importsDirs = [ ];
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
  #     Extra macOS LaunchAgents; symlinked into ~/Library/LaunchAgents/.
  #
  #   ~/.config/dotfiles/opencode/opencode.*.json
  #     OpenCode JSON fragments (deep-merged in filename order).
}
