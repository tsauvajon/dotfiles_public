# Git configuration via Home Manager.
#
# Replaces:
# - The Rust setup tool's `generate.rs` template substitution that
#   produced ~/.gitconfig from config/git/gitconfig + private values.
# - The packages list in `home/git.nix` (kept here for the same set).
#
# Identity (name, email, signingKey) comes from the private flake,
# which reads it from ~/.config/dotfiles/config.toml so the user keeps
# editing one file. Optional ~/.config/dotfiles/extra.gitconfig is
# included as a per-machine overlay.
{
  pkgs,
  lib,
  inputs,
  ...
}:

let
  privateGit = inputs.private.git;
in
{
  home.packages = with pkgs; [
    delta
    gh
    glab
  ];

  programs.git = {
    enable = true;

    signing = {
      key = privateGit.signingKey;
      signByDefault = true;
      format = "openpgp";
    };

    includes = lib.optional (privateGit.extraConfigInclude != null) {
      path = toString privateGit.extraConfigInclude;
    };

    # Single `settings` attrset replaces the legacy `userName`,
    # `userEmail`, and `extraConfig` options that home-manager renamed
    # in mid-2026.
    settings = {
      user = {
        name = privateGit.name;
        email = privateGit.email;
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
