# Shell and terminal workflow tools, including nixGL wrapping for
# graphical terminals on Linux.
{
  config,
  pkgs,
  lib,
  inputs,
  nixglNvidiaVersion ? null,
  nixglNvidiaHash ? null,
  ...
}:

let
  fishPath = "${config.home.profileDirectory}/bin/fish";

  wrapWithNixGL = import ./lib/wrap-with-nixgl.nix {
    inherit pkgs;
    inherit (inputs) nixgl nixgl-nixpkgs;
    nvidiaVersion = nixglNvidiaVersion;
    nvidiaHash = nixglNvidiaHash;
  };
in
{
  # tmux is provided by programs.tmux in home/programs/tmux.nix.
  home.packages = [
    (wrapWithNixGL pkgs.alacritty "alacritty")
    pkgs.bash
    pkgs.coreutils
    pkgs.curl
    pkgs.fish
    pkgs.just
    (wrapWithNixGL pkgs.kitty "kitty")
    pkgs.socat
    pkgs.websocat
    pkgs.zellij
    pkgs.zsh
    pkgs.zsh-autosuggestions
    pkgs.zsh-completions
    pkgs.zsh-powerlevel10k
    pkgs.zsh-syntax-highlighting
  ];

  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
    enableZshIntegration = true;
  };

  # Changing login shells mutates system state; standalone Home Manager
  # only warns with the exact commands to run when fish is not active.
  home.activation.warnFishLoginShell = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        fish_path="${fishPath}"
        current_shell="''${SHELL:-}"
        found_login_shell=0

        if command -v getent >/dev/null 2>&1; then
          passwd_entry="$(getent passwd "$(id -un)" 2>/dev/null || true)"
          if [ -n "$passwd_entry" ]; then
            current_shell="''${passwd_entry##*:}"
            found_login_shell=1
          fi
        fi

        if [ "$found_login_shell" -eq 0 ]; then
          if [ -x /usr/bin/dscl ]; then
            dscl_shell="$(/usr/bin/dscl . -read "$HOME" UserShell 2>/dev/null || true)"
          elif command -v dscl >/dev/null 2>&1; then
            dscl_shell="$(dscl . -read "$HOME" UserShell 2>/dev/null || true)"
          else
            dscl_shell=""
          fi

          case "$dscl_shell" in
            "UserShell: "*) current_shell="''${dscl_shell#UserShell: }" ; found_login_shell=1 ;;
          esac
        fi

    if [ "''${current_shell##*/}" != fish ]; then
      printf '%s\n' \
        'warning: fish is installed by Home Manager, but your login shell is not fish.' \
        "" \
        "Current login shell: ''${current_shell:-unknown}" \
        "Fish installed at:    $fish_path" \
        ""

      if [ ! -r /etc/shells ] || ! grep -qxF "$fish_path" /etc/shells; then
        printf '%s\n' \
          'Before chsh can use this fish path, add it to /etc/shells:' \
          "" \
          "  sudo sh -c 'grep -qxF \"$fish_path\" /etc/shells || echo \"$fish_path\" >> /etc/shells'" \
          ""
      fi

      printf '%s\n' \
        'Then set fish as your default login shell:' \
        "" \
        "  chsh -s \"$fish_path\"" \
        ""
    fi
  '';
}
