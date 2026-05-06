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
    nix run nixpkgs#gnupg -- --quick-generate-key "Name <email>" ed25519 default 1y
    nix run nixpkgs#gnupg -- --list-secret-keys --keyid-format long
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
  # works from non-TTY contexts (IDEs, Finder-launched git GUIs).
  # `force = true` overrides an existing single-line user config; if
  # you keep custom gpg-agent settings (cache TTLs, etc.), drop this
  # block and add the pinentry-program line manually.
  home.file = lib.mkIf pkgs.stdenv.isDarwin {
    ".gnupg/gpg-agent.conf" = {
      force = true;
      text = ''
        pinentry-program ${pkgs.pinentry_mac}/bin/pinentry-mac
      '';
    };
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
