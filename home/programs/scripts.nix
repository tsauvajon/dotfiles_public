# Small shell scripts shared across shells.
#
# When a shell function doesn't need to manipulate the caller's shell
# state (cwd, env, history) it's just a wrapper script and can live as
# a standalone executable on PATH. Both shells then call the same
# binary — no per-shell duplication.
#
# Functions that DO need shell-state access (cd-task, y, history) stay
# as per-shell functions, generated via cross-shell-functions.nix.
{ pkgs, ... }:

{
  home.packages = [
    # ripgrep + delta with default `-C2` context. Replaces what was
    # an `rd()` function in zshrc and a fish function file.
    (pkgs.writeShellApplication {
      name = "rd";
      runtimeInputs = [ pkgs.ripgrep pkgs.delta ];
      text = ''
        context="-C2"
        for arg in "$@"; do
          case "$arg" in
            -C*) context="" ;;
          esac
        done
        if [ -n "$context" ]; then
          rg --json "$context" "$@" | delta
        else
          rg --json "$@" | delta
        fi
      '';
    })

    # Copy <file> to <file>.bak. Trivial wrapper.
    (pkgs.writeShellApplication {
      name = "backup";
      text = ''
        if [ "$#" -ne 1 ]; then
          echo "usage: backup <file>" >&2
          exit 2
        fi
        cp -- "$1" "$1.bak"
      '';
    })
  ];
}
