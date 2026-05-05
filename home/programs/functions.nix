# Cross-shell function bodies.
#
# Each entry produces a synchronised pair at HM build time:
#   ~/.config/zsh/functions/<name>.zsh
#   ~/.config/fish/functions/<name>.fish
#
# Adding a function: drop a new attr below with both shells' bodies
# and rerun `bash setup.sh`. Both shells will pick it up on next
# login.
{ ... }:

{
  programs.crossShellFunctions = {
    cd-task = {
      description = "cd to a task worktree path";
      zshBody = ''
        local dir
        dir="$(task path "$@")" || return $?
        cd "$dir"
      '';
      fishBody = ''
        cd (task path $argv)
      '';
    };

    y = {
      description = "open yazi and cd into its last cwd on exit";
      zshBody = ''
        local tmp cwd
        tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
        yazi "$@" --cwd-file="$tmp"
        if cwd="$(command cat -- "$tmp")" && [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
          builtin cd -- "$cwd"
        fi
        rm -f -- "$tmp"
      '';
      fishBody = ''
        set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
        yazi $argv --cwd-file="$tmp"
        set -l cwd (command cat -- "$tmp")
        if test -n "$cwd"; and test "$cwd" != "$PWD"
            builtin cd -- "$cwd"
        end
        rm -f -- "$tmp"
      '';
    };

    history = {
      description = "show timestamps in history output";
      zshBody = ''
        builtin fc -li "$@"
      '';
      fishBody = ''
        builtin history --show-time='%F %T '
      '';
    };
  };
}
