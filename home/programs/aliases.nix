# Cross-shell alias attrset.
#
# Define every alias that should exist in both zsh and fish here.
# `home/programs/cross-shell-aliases.nix` consumes this and emits the
# two synchronised fragments. Per-shell-only aliases (Arch pacman
# stuff in fish, docker shortcuts in zsh, etc.) stay in their per-shell
# rc files; only the truly common subset belongs here.
#
# Adding an alias: just add a new attr below and rerun `bash setup.sh`.
# Both shells will pick it up on next login.
{ ... }:

{
  programs.crossShellAliases.aliases = {
    # cd helpers
    cdt = "cd-task";

    # Cargo / Rust
    fmt = "cargo fmt";

    # Git — single-letter
    g = "git";

    # Git — commit / amend
    gam = "git commit -am";
    gan = "git commit --all --amend --no-edit";
    gcb = "git checkout -b";
    gcl = "git clone --recurse-submodules";
    gcm = "git commit -m";
    gcn = "git commit --amend --no-edit";

    # Git — log / status
    glog = "git log --oneline --decorate --graph";
    gss = "git status --short";

    # Git — push / pull
    gp = "git push";
    gpl = "git pull --rebase --recurse-submodules";
    gpu = "git push --set-upstream";

    # Git — rebase
    grb = "git fetch && git rebase --interactive --autosquash";

    # Zoxide
    j = "z";

    # Listing (eza)
    la = "eza -a --color=always --group-directories-first --git --icons --no-user --no-time --no-permissions";
    ll = "eza -l --color=always --group-directories-first --git --icons --no-user --no-time --no-permissions";
    ls = "eza -al --color=always --group-directories-first --git --icons --no-user --no-time --no-permissions";

    # Shorthands
    md = "mdterm";
    oc = "opencode";

    # Task
    t = "task";
    td = "task detach";
    tf = "task finish";
    tp = "task path";
    ts = "task start";

    # Editor
    vim = "nvim";
  };
}
