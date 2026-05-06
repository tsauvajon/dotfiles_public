# Home Manager activation scripts:
#   - Removes managed symlinks at known paths that may collide with
#     `checkLinkTargets`.
#   - Removes the unused ~/.config/dotfiles/path file if present.
#   - Runs `task bootstrap --yes` once HM has finished linking files.
#
# Each activation block runs after the named DAG entry. Ordering is:
#   writeBoundary -> [our cleanup] -> linkGeneration -> [task bootstrap].
{
  config,
  lib,
  pkgs,
  dotfilesRoot,
  ...
}:

let
  inherit (lib.hm.dag) entryAfter entryBefore;

  # Paths HM owns. Removed before `checkLinkTargets` runs so that any
  # pre-existing symlink into a managed root does not abort activation
  # with "would be clobbered".
  managedPaths = [
    ".config/opencode/AGENTS.md"
    ".config/opencode/opencode.json"
    ".config/opencode/package.json"
    ".config/opencode/commands"
    ".config/opencode/skills"
    ".config/opencode/agents"
    ".config/opencode/plugins"
    ".tmux.conf"
    ".tmux/plugins"
    ".gitconfig"
    ".config/hypr"
    ".config/mako"
    ".config/rofi"
    ".config/waybar"
    ".config/goto/config.yml"
    ".config/goto/database.yml"
    ".config/task/config.toml"
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

  cleanupScript = pkgs.writeShellScript "dotfiles-cleanup-managed" ''
    set -eu
    home="${homeDir}"
    managed_roots=(${lib.concatMapStringsSep " " (r: "'${r}'") managedRoots})
    for rel in ${lib.concatMapStringsSep " " (p: "'${p}'") managedPaths}; do
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
      fi
    done
  '';
in
{
  home.activation = {
    # Remove the unused ~/.config/dotfiles/path file if present.
    removeDotfilesPath = entryBefore [ "checkLinkTargets" ] ''
      rm -f "${homeDir}/.config/dotfiles/path"
    '';

    # Clear pre-existing managed symlinks before HM tries to create
    # its own, otherwise checkLinkTargets aborts the activation.
    cleanupManagedDotfiles = entryBefore [ "checkLinkTargets" ] ''
      ${cleanupScript}
    '';

    # `task bootstrap` ensures workspace directories are present. Run after
    # HM linking completes so task can find its config.
    taskBootstrap = entryAfter [ "linkGeneration" ] ''
      task_bin="${homeDir}/.cargo/bin/task"
      if [ -x "$task_bin" ]; then
        "$task_bin" bootstrap --yes || true
      fi
    '';
  };
}
