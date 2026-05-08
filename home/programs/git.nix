# Git configuration via Home Manager.
#
# Identity (name, email, signingKey) comes from the private flake at
# ~/.config/dotfiles/flake.nix under the `git` attribute. The build
# throws if any of those three fields is empty so missing identity is
# caught loudly rather than producing unsigned commits as "". setup.sh
# fills signingKey automatically when it generates or detects a GPG key.
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
  fill in `git.name` and `git.email`, then rerun setup.sh so it can
  generate or detect a GPG key and fill `git.signingKey`.

  To inspect or reprint key upload commands manually:
    ./scripts/bootstrap-keys.sh --show
'';
{

  home.packages =
    with pkgs;
    [
      delta
      gh
      git-lfs
      glab
      gnupg
      pre-commit
    ]
    ++ lib.optional stdenv.isDarwin pinentry_mac;

  # Wire gpg-agent to use pinentry-mac on darwin so commit signing
  # works from non-TTY contexts (IDEs, Finder-launched git GUIs). The
  # heavy lifting lives in scripts/lib/configure-gpg-pinentry.sh so it
  # can be exercised by the configure-gpg-pinentry-test flake check
  # (covers missing-file, empty, single-line, multi-line, and
  # preserves-other-settings shapes).
  home.activation = lib.mkIf pkgs.stdenv.isDarwin {
    configureGpgAgentPinentry = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      ${pkgs.bash}/bin/bash ${../../scripts/lib/configure-gpg-pinentry.sh} \
        "$HOME/.gnupg/gpg-agent.conf" \
        "${pkgs.pinentry_mac}/bin/pinentry-mac"
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
