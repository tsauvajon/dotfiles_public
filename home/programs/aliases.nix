# Cross-shell alias attrset.
#
# Define every alias that should exist in both zsh and fish here.
# `home/programs/cross-shell-aliases.nix` consumes this and emits the
# two synchronised fragments. Per-shell-only aliases (Arch pacman
# stuff in fish, machine-private stuff in extras.zsh, etc.) stay in
# their per-shell rc files; only the truly common subset belongs here.
#
# Adding an alias: just add a new attr below and rerun `bash setup.sh`.
# Both shells will pick it up on next login.
{ ... }:

{
  programs.crossShellAliases.aliases = {
    # cd helpers
    cdt = "cd-task";

    # Cargo / Rust
    cov = "cargo llvm-cov nextest --lcov --all --output-path lcov.info && rm -rf target/debug/coverage && grcov lcov.info -s . --binary-path ./target/debug/ -t html --excl-line='^\\s*(\\.await).*' --excl-start='mod test' -o ./target/debug/coverage/ && open ./target/debug/coverage/index.html";
    fmt = "cargo fmt";

    # Docker
    dco = "docker-compose";
    dk = "docker";
    dkps = "docker ps";
    dksr = "docker stop $(docker ps -qa) && docker rm $(docker ps -qa)";
    dps = "docker ps";

    # Git — single-letter
    g = "git";

    # Git — add / diff / fetch
    ga = "git add";
    gd = "git diff";
    gf = "git fetch";

    # Git — commit / amend
    gam = "git commit -am";
    gan = "git commit --all --amend --no-edit";
    gc = "git commit";
    gcb = "git checkout -b";
    gcl = "git clone --recurse-submodules";
    gcm = "git commit -m";
    gcn = "git commit --amend --no-edit";
    gco = "git checkout";

    # Git — branch / merge / rebase
    gbd = "git branch -d";
    gbD = "git branch -D";
    gm = "git merge";
    gr = "git rebase";
    grb = "git fetch && git rebase --interactive --autosquash";

    # Git — log / status
    glog = "git log --oneline --decorate --graph";
    gss = "git status --short";

    # Git — push / pull
    gp = "git push";
    gpl = "git pull --rebase --recurse-submodules";
    gpu = "git push --set-upstream";

    # Git — remote
    gra = "git remote add";
    grr = "git remote remove";
    grv = "git remote --verbose";

    # ls replacements
    l = "eza -lah --color=always --group-directories-first --git --icons --no-user --no-time --no-permissions";
    la = "eza -a --color=always --group-directories-first --git --icons --no-user --no-time --no-permissions";
    ll = "eza -l --color=always --group-directories-first --git --icons --no-user --no-time --no-permissions";
    ls = "eza -al --color=always --group-directories-first --git --icons --no-user --no-time --no-permissions";
    lt = "eza -aT --color=always --group-directories-first --git --icons --no-user --no-time --no-permissions";

    # Other shorthands
    gt = "goto";
    h = "hx";
    md = "mdterm";
    oc = "opencode";

    # Task
    t = "task";
    td = "task detach";
    tf = "task finish";
    tp = "task path";
    ts = "task start";

    # Tar shortcuts
    untar = "tar -zxvf";

    # Tool replacements: override a classic tool with a modern one.
    # Every binary on the right MUST be on PATH on every machine
    # (provided by Nix HM modules in this repo).
    btop = "htop";       # btop name kept for muscle memory
    cat = "bat";         # syntax-highlighting pager
    less = "bat";        # syntax-highlighting pager
    du = "dust";         # rust replacement, prettier output
    find = "fd";         # rust replacement, friendlier syntax
    lf = "y";            # delegate to the yazi `y` wrapper (cd-on-exit)
    nano = "hx";         # editor reflex hijack
    ranger = "y";        # same — old-habits redirect to yazi
    top = "htop";        # standard quality-of-life override
    vi = "nvim";         # bring vi habits to nvim
    vim = "nvim";        # same for vim

    # Zoxide
    j = "z";
  };
}
