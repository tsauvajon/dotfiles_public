# Setup-time bootstrap moved into Home Manager activation scripts.
#
# Replaces the Rust setup tool's tail end:
#   - Records the dotfiles path to ~/.config/dotfiles/path.
#   - Removes legacy Rust-managed symlinks so HM does not trip over
#     `checkLinkTargets`.
#   - Runs `task bootstrap --yes` once HM has finished linking files.
#
# Each activation block runs after the named DAG entry. Ordering is:
#   writeBoundary -> [our cleanup] -> linkGeneration -> [path record,
#   task bootstrap].
{
  config,
  lib,
  pkgs,
  dotfilesRoot,
  ...
}:

let
  inherit (lib.hm.dag) entryAfter entryBefore;

  # Paths that were managed by the Rust setup tool in earlier phases.
  # HM owns these now; clear them on first run after Phase 7 so HM
  # activation does not abort with "would be clobbered".
  legacyPaths = [
    # Phase 3 (opencode merges)
    ".config/opencode/AGENTS.md"
    ".config/opencode/opencode.json"
    ".config/opencode/package.json"
    ".config/opencode/commands"
    ".config/opencode/skills"
    ".config/opencode/agents"
    ".config/opencode/plugins"
    # Phase 4 (programs.tmux, programs.git, desktop modules)
    ".tmux.conf"
    ".tmux/plugins"
    ".gitconfig"
    ".config/hypr"
    ".config/mako"
    ".config/rofi"
    ".config/waybar"
    # Phase 5 (programs.gotoLinks, programs.task)
    ".config/goto/config.yml"
    ".config/goto/database.yml"
    ".config/task/config.toml"
    # Phase 6 (files.nix + programs/{aerospace,alacritty,cargo}.nix)
    ".profile"
    ".bashrc"
    ".bash_profile"
    ".fish_profile"
    ".tool-versions"
    ".nix-channels"
    ".aerospace.toml"
    ".cargo/config.toml"
    ".config/wayland-env.sh"
    ".config/espflash"
    ".config/fish"
    ".config/helix"
    ".config/kitty"
    ".config/bat"
    ".config/fzf"
    ".config/eza"
    ".config/yazi"
    ".config/zellij/config.kdl"
    ".config/zellij/themes/catppuccin.kdl"
    ".config/obsidian/Preferences"
    ".config/keepassxc/keepassxc.ini"
    ".config/alacritty/alacritty.toml"
    ".config/alacritty/themes"
    ".ssh/config"
    # Retired in earlier phases
    "flakes"
  ];

  homeDir = config.home.homeDirectory;

  # Roots a managed symlink target may point into. Only symlinks
  # pointing into one of these are removed by the cleanup; foreign
  # symlinks and real files are preserved.
  managedRoots = [
    dotfilesRoot
    (homeDir + "/.config/dotfiles")
    (homeDir + "/.local/share/dotfiles")
  ];

  cleanupScript = pkgs.writeShellScript "dotfiles-cleanup-legacy" ''
    set -eu
    home="${homeDir}"
    managed_roots=(${lib.concatMapStringsSep " " (r: "'${r}'") managedRoots})
    for rel in ${lib.concatMapStringsSep " " (p: "'${p}'") legacyPaths}; do
      dest="$home/$rel"
      if [ -L "$dest" ]; then
        target=$(readlink "$dest")
        for root in "''${managed_roots[@]}"; do
          case "$target" in
            "$root"*)
              rm -f "$dest"
              break
              ;;
          esac
        done
      elif [ -f "$dest" ] && [ ! -s "$dest" ]; then
        # empty regular file (stale placeholder)
        rm -f "$dest"
      fi
    done
  '';
in
{
  home.activation = {
    # Record the dotfiles path so future invocations of setup.sh and
    # the `nix run path:./` helper know where the live repo is.
    recordDotfilesPath = entryAfter [ "writeBoundary" ] ''
      mkdir -p "${homeDir}/.config/dotfiles"
      printf '%s\n' "${dotfilesRoot}" > "${homeDir}/.config/dotfiles/path"
    '';

    # Clear legacy Rust-managed symlinks before HM tries to create
    # its own, otherwise checkLinkTargets aborts the activation.
    cleanupLegacyDotfiles = entryBefore [ "checkLinkTargets" ] ''
      ${cleanupScript}
    '';

    # `task bootstrap` ensures the asdf node plugin and workspace
    # directories are present. Run after HM linking completes so
    # task/asdf can find their configs.
    taskBootstrap = entryAfter [ "linkGeneration" ] ''
      task_bin="${homeDir}/.cargo/bin/task"
      if [ -x "$task_bin" ]; then
        "$task_bin" bootstrap --yes || true
      fi
    '';
  };
}
