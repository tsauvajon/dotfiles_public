# Git configuration via Home Manager.
#
# Identity (name, email, signingKey) comes from the private flake at
# ~/.config/dotfiles/flake.nix under the `git` attribute. The build
# throws if any of those three fields is empty so missing identity is
# caught loudly rather than producing unsigned commits as "".
#
# Optional ~/.config/dotfiles/extra.gitconfig is included as a
# per-machine overlay when `git.extraConfigInclude` points at it.
{
  pkgs,
  lib,
  inputs,
  ...
}:

let
  privateGit = inputs.private.git or { };
  name = privateGit.name or "";
  email = privateGit.email or "";
  signingKey = privateGit.signingKey or "";
  extraConfigInclude = privateGit.extraConfigInclude or null;

  hasIdentity = name != "" && email != "" && signingKey != "";
in
assert lib.assertMsg hasIdentity ''

  Private git identity not set. Edit ~/.config/dotfiles/flake.nix and
  fill in `git.name`, `git.email`, and `git.signingKey`. See
  private.example.nix in the dotfiles repo for the expected shape.

  No GPG key yet? Generate one with:
    nix --extra-experimental-features 'nix-command flakes' run nixpkgs#gnupg -- \
      --quick-generate-key "Name <email>" ed25519 default 1y
    nix --extra-experimental-features 'nix-command flakes' run nixpkgs#gnupg -- \
      --list-secret-keys --keyid-format long
'';
{

  home.packages =
    with pkgs;
    [
      delta
      gh
      glab
      gnupg
    ]
    ++ lib.optional stdenv.isDarwin pinentry_mac;

  # Wire gpg-agent to use pinentry-mac on darwin so commit signing
  # works from non-TTY contexts (IDEs, Finder-launched git GUIs). This
  # preserves existing gpg-agent settings such as cache TTLs.
  home.activation = lib.mkIf pkgs.stdenv.isDarwin {
    configureGpgAgentPinentry = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      conf="$HOME/.gnupg/gpg-agent.conf"
      pinentry_line="pinentry-program ${pkgs.pinentry_mac}/bin/pinentry-mac"

      ${pkgs.coreutils}/bin/mkdir -p "$HOME/.gnupg"
      ${pkgs.coreutils}/bin/chmod 700 "$HOME/.gnupg"

      if [ -L "$conf" ]; then
        target="$(${pkgs.coreutils}/bin/readlink "$conf" || true)"
        case "$target" in
          /nix/store/*) ${pkgs.coreutils}/bin/rm -f "$conf" ;;
        esac
      fi

      if [ -f "$conf" ]; then
        tmp="$conf.tmp.$$"
        found=0
        while IFS= read -r line || [ -n "$line" ]; do
          case "$line" in
            "pinentry-program "*)
              if [ "$found" -eq 0 ]; then
                printf '%s\n' "$pinentry_line"
                found=1
              fi
              ;;
            *) printf '%s\n' "$line" ;;
          esac
        done < "$conf" > "$tmp"
        if [ "$found" -eq 0 ]; then
          printf '%s\n' "$pinentry_line" >> "$tmp"
        fi
        ${pkgs.coreutils}/bin/mv "$tmp" "$conf"
      else
        printf '%s\n' "$pinentry_line" > "$conf"
      fi

      ${pkgs.gnupg}/bin/gpgconf --kill gpg-agent >/dev/null 2>&1 || true
    '';
  };

  programs.git = {
    enable = true;

    signing = {
      key = signingKey;
      signByDefault = true;
      format = "openpgp";
    };

    includes = lib.optional (extraConfigInclude != null) {
      path = toString extraConfigInclude;
    };

    # Single `settings` attrset replaces the legacy `userName`,
    # `userEmail`, and `extraConfig` options that home-manager renamed
    # in mid-2026.
    settings = {
      user = {
        inherit name email;
      };
      init.defaultBranch = "master";
      core = {
        editor = "hx";
        pager = "delta";
      };
      push.autoSetupRemote = true;
      pack = {
        windowMemory = "100m";
        packSizeLimit = "100m";
        threads = 1;
        deltaCacheSize = "512m";
      };
      filter."lfs" = {
        clean = "git-lfs clean -- %f";
        smudge = "git-lfs smudge -- %f";
        process = "git-lfs filter-process";
        required = true;
      };
      interactive.diffFilter = "delta --color-only";
      delta = {
        paging = "always";
        navigate = true;
        dark = true;
        side-by-side = true;
        line-numbers = true;
        hyperlinks = true;
        syntax-theme = "Catppuccin Mocha";
      };
      merge = {
        conflictStyle = "zdiff3";
        tool = "vimdiff";
      };
      mergetool.prompt = false;
    };
  };
}
