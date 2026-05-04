mod config;
mod external;

mod link;

mod plists;


use anyhow::Result;
use config::{Paths, PrivateConfig};

fn main() -> Result<()> {
    if std::env::args().any(|a| a == "--check") {
        eprintln!("--check is deprecated. Use:");
        eprintln!(
            "  nix build --impure --dry-run path:.#homeConfigurations.<host>.activationPackage"
        );
        std::process::exit(1);
    }

    let paths = Paths::resolve()?;

    let legacy_private = paths.dotfiles_config.join("private.toml");
    if config::migrate_private_to_config(&legacy_private, &paths.config_toml)? {
        println!(
            "MIGRATED: renamed private.toml to config.toml in {}",
            paths.dotfiles_config.display()
        );
    }

    if config::migrate_skip_links(&paths.config_toml)? {
        println!(
            "MIGRATED: renamed skip_links to skip_destinations in {}",
            paths.config_toml.display()
        );
    }

    if config::migrate_skip_sources_paths(&paths.config_toml)? {
        println!(
            "MIGRATED: rewrote home/* paths to config/* in skip_sources of {}",
            paths.config_toml.display()
        );
    }

    if config::migrate_rules_mode_key(&paths.config_toml)? {
        println!(
            "MIGRATED: renamed agents_mode to rules_mode in {}",
            paths.config_toml.display()
        );
    }

    if config::migrate_dir(
        &paths.dotfiles_config.join("private-AGENTS"),
        &paths.opencode_rules,
    )? {
        println!(
            "MIGRATED: moved rules overlays from {}/private-AGENTS to {}",
            paths.dotfiles_config.display(),
            paths.opencode_rules.display()
        );
    }

    let private_opencode_skills = paths.dotfiles_config.join("opencode/skills");
    if config::migrate_dir(
        &paths.dotfiles_config.join("private-skills"),
        &private_opencode_skills,
    )? {
        println!(
            "MIGRATED: moved skills from {}/private-skills to {}",
            paths.dotfiles_config.display(),
            private_opencode_skills.display()
        );
    }

    if config::migrate_file(
        &paths.dotfiles_config.join("private-opencode.json"),
        &paths.opencode_json,
    )? {
        println!(
            "MIGRATED: moved private-opencode.json to {}",
            paths.opencode_json.display()
        );
    }

    let private_cfg = PrivateConfig::load(&paths.config_toml)?;
    let skip_norms = private_cfg.skip_norms(&paths.home);
    let skip_source_norms = private_cfg.skip_source_norms();

    run_setup(&paths, &skip_norms, &skip_source_norms)
}

fn run_setup(
    paths: &Paths,
    skip_norms: &[String],
    skip_source_norms: &[String],
) -> Result<()> {
    log("Recording dotfiles path");
    std::fs::create_dir_all(&paths.dotfiles_config)?;
    std::fs::write(
        paths.dotfiles_config.join("path"),
        format!("{}\n", paths.dotfiles.display()),
    )?;

    log("Linking LaunchAgents plists");
    plists::link_all(paths, skip_norms, skip_source_norms)?;

    // After Phase 6, all dotfiles symlinks live in home/files.nix and
    // home/programs/*.nix. Clear any legacy Rust-managed symlinks so
    // HM activation does not trip over `checkLinkTargets`.
    for relative in [
        // Phase 3 (opencode merges)
        ".config/opencode/AGENTS.md",
        ".config/opencode/opencode.json",
        ".config/opencode/package.json",
        ".config/opencode/commands",
        ".config/opencode/skills",
        ".config/opencode/agents",
        ".config/opencode/plugins",
        // Phase 4 (programs.tmux, programs.git, desktop modules)
        ".tmux.conf",
        ".tmux/plugins",
        ".gitconfig",
        ".config/hypr",
        ".config/mako",
        ".config/rofi",
        ".config/waybar",
        // Phase 5 (programs.gotoLinks, programs.task)
        ".config/goto/config.yml",
        ".config/goto/database.yml",
        ".config/task/config.toml",
        // Phase 6 (files.nix + programs/{aerospace,alacritty,cargo}.nix)
        ".profile",
        ".bashrc",
        ".bash_profile",
        ".fish_profile",
        ".tool-versions",
        ".nix-channels",
        ".aerospace.toml",
        ".cargo/config.toml",
        ".config/wayland-env.sh",
        ".config/espflash",
        ".config/fish",
        ".config/helix",
        ".config/kitty",
        ".config/bat",
        ".config/fzf",
        ".config/eza",
        ".config/yazi",
        ".config/zellij/config.kdl",
        ".config/zellij/themes/catppuccin.kdl",
        ".config/obsidian/Preferences",
        ".config/keepassxc/keepassxc.ini",
        ".config/alacritty/alacritty.toml",
        ".config/alacritty/themes",
        ".ssh/config",
        // Retired earlier
        "flakes",
    ] {
        link::remove_managed_link_if_present(&paths.home.join(relative), paths)?;
    }

    log("Ensuring workspace directories");
    let dev = &paths.dev_root;
    std::fs::create_dir_all(dev.join("repos"))?;
    std::fs::create_dir_all(dev.join("wt"))?;
    std::fs::create_dir_all(dev.join("detached"))?;

    external::install_home_manager(paths)?;
    external::run_task_bootstrap(&paths.home)?;

    if !paths.config_toml.exists() {
        println!(
            "tip: place config.toml at {} to configure git identity and network URLs",
            paths.config_toml.display()
        );
    }
    // generate.rs was retired in Phase 5 — goto and task templates are
    // owned by their upstream Home Manager modules now.

    let opencode_private = &paths.dotfiles_config.join("opencode");
    for name in &["commands", "skills", "agents", "plugins"] {
        let dir = opencode_private.join(name);
        if !dir.exists() {
            println!(
                "tip: place private opencode {} under {}",
                name,
                dir.display()
            );
        }
    }
    if !paths.opencode_rules.exists() {
        println!(
            "tip: place private opencode rules overlays under {}/<name>.md",
            paths.opencode_rules.display()
        );
    }
    if !paths.opencode_json.exists() {
        println!(
            "tip: place private opencode config at {} to override opencode.json (eg. MCP servers)",
            paths.opencode_json.display()
        );
    }
    let private_ssh_config = paths.dotfiles_config.join("ssh/config");
    if !private_ssh_config.exists() {
        println!(
            "tip: place private SSH hosts at {} (included from ~/.ssh/config)",
            private_ssh_config.display()
        );
    }

    log("Done");
    println!("Next steps:");
    println!("  1) Restart your shell");
    println!("  2) Run opencode and /connect once");
    println!("  3) Run task doctor");

    Ok(())
}

fn log(msg: &str) {
    println!("==> {msg}");
}

fn warn(msg: &str) {
    eprintln!("warning: {msg}");
}
