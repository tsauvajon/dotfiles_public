mod config;
mod external;
mod generate;
mod link;
mod merge;
mod plists;


use anyhow::Result;
use config::{Paths, PrivateConfig};

fn main() -> Result<()> {
    let check_mode = std::env::args().any(|a| a == "--check");

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

    if check_mode {
        return run_check(&paths, &private_cfg, &skip_norms, &skip_source_norms);
    }

    run_setup(&paths, &private_cfg, &skip_norms, &skip_source_norms)
}

fn run_setup(
    paths: &Paths,
    private_cfg: &PrivateConfig,
    skip_norms: &[String],
    skip_source_norms: &[String],
) -> Result<()> {
    log("Recording dotfiles path");
    std::fs::create_dir_all(&paths.dotfiles_config)?;
    std::fs::write(
        paths.dotfiles_config.join("path"),
        format!("{}\n", paths.dotfiles.display()),
    )?;

    log("Linking home files");
    let d = &paths.dotfiles;
    let h = &paths.home;
    // tmux is owned by Home Manager since Phase 4 (programs.tmux).
    link::managed_link(
        &d.join("config/shell/profile"),
        &h.join(".profile"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/shell/fish_profile"),
        &h.join(".fish_profile"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/shell/bashrc"),
        &h.join(".bashrc"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/shell/bash_profile"),
        &h.join(".bash_profile"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/nix/nix-channels"),
        &h.join(".nix-channels"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/asdf/tool-versions"),
        &h.join(".tool-versions"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    // Clean up symlinks retired by earlier phases:
    // - ~/flakes (Phase 2: per-domain flakes removed)
    // - ~/.tmux.conf and ~/.tmux/plugins (Phase 4: programs.tmux)
    link::remove_managed_link_if_present(&h.join("flakes"), paths)?;
    link::remove_managed_link_if_present(&h.join(".tmux.conf"), paths)?;
    link::remove_managed_link_if_present(&h.join(".tmux/plugins"), paths)?;

    log("Linking config files");
    link::managed_link(
        &d.join("config/wayland-env.sh"),
        &h.join(".config/wayland-env.sh"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/espflash"),
        &h.join(".config/espflash"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/fish"),
        &h.join(".config/fish"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/helix"),
        &h.join(".config/helix"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    // hypr, mako, rofi are owned by Home Manager since Phase 4
    // (home/desktop/{hyprland,mako,rofi}.nix on Linux). On macOS the
    // modules evaluate to no-ops.
    link::managed_link(
        &d.join("config/kitty"),
        &h.join(".config/kitty"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/obsidian/Preferences"),
        &h.join(".config/obsidian/Preferences"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/keepassxc/keepassxc.ini"),
        &h.join(".config/keepassxc/keepassxc.ini"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/ssh/config"),
        &h.join(".ssh/config"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    // waybar is owned by Home Manager since Phase 4 (home/desktop/waybar.nix).
    link::managed_link(
        &d.join("config/bat"),
        &h.join(".config/bat"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/fzf"),
        &h.join(".config/fzf"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/eza"),
        &h.join(".config/eza"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/yazi"),
        &h.join(".config/yazi"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/zellij/config.kdl"),
        &h.join(".config/zellij/config.kdl"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &d.join("config/zellij/catppuccin/catppuccin.kdl"),
        &h.join(".config/zellij/themes/catppuccin.kdl"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &paths.dotfiles_config.join("goto/database.yml"),
        &h.join(".config/goto/database.yml"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;

    log("Linking LaunchAgents plists");
    plists::link_all(paths, skip_norms, skip_source_norms)?;

    // OpenCode (Phase 3), tmux + git + desktop tools (Phase 4) are
    // owned by Home Manager. Clear any legacy symlinks the Rust tool
    // used to create so HM activation does not trip over
    // `checkLinkTargets`.
    for relative in [
        ".config/opencode/AGENTS.md",
        ".config/opencode/opencode.json",
        ".config/opencode/package.json",
        ".config/opencode/commands",
        ".config/opencode/skills",
        ".config/opencode/agents",
        ".config/opencode/plugins",
        ".config/hypr",
        ".config/mako",
        ".config/rofi",
        ".config/waybar",
    ] {
        link::remove_managed_link_if_present(&paths.home.join(relative), paths)?;
    }

    merge::merge_aerospace(paths, skip_norms, skip_source_norms)?;
    merge::merge_cargo(paths, skip_norms, skip_source_norms)?;
    merge::merge_alacritty(paths, skip_norms, skip_source_norms)?;
    merge::merge_task(paths, skip_norms, skip_source_norms)?;

    log("Ensuring workspace directories");
    let dev = &paths.dev_root;
    std::fs::create_dir_all(dev.join("repos"))?;
    std::fs::create_dir_all(dev.join("wt"))?;
    std::fs::create_dir_all(dev.join("detached"))?;

    external::install_home_manager(paths)?;
    external::run_task_bootstrap(&paths.home)?;

    if paths.config_toml.exists() {
        generate::generate_private_files(paths, private_cfg, skip_norms, skip_source_norms)?;
    } else {
        println!(
            "tip: place config.toml at {} to configure git identity and network URLs",
            paths.config_toml.display()
        );
    }

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
    let private_goto_db = paths.dotfiles_config.join("goto/database.yml");
    if !private_goto_db.exists() {
        println!("tip: place goto bookmarks at {}", private_goto_db.display());
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

fn run_check(
    paths: &Paths,
    private_cfg: &PrivateConfig,
    _skip_norms: &[String],
    skip_source_norms: &[String],
) -> Result<()> {
    use std::collections::BTreeMap;

    let temp_dir = std::env::temp_dir().join("dotfiles-setup-check");
    if temp_dir.exists() {
        std::fs::remove_dir_all(&temp_dir)?;
    }

    // Create a shadow Paths that writes generated files to temp
    let shadow_build = temp_dir.join("build");
    std::fs::create_dir_all(&shadow_build)?;

    let shadow_paths = Paths {
        dist: shadow_build.clone(),
        ..paths.clone()
    };

    // Generate all files into temp. OpenCode merges are owned by HM
    // since Phase 3 and are no longer compared here.
    merge::merge_aerospace_to(&shadow_paths, skip_source_norms)?;
    merge::merge_cargo_to(&shadow_paths, skip_source_norms)?;
    merge::merge_alacritty_to(&shadow_paths, skip_source_norms)?;
    merge::merge_task_to(&shadow_paths, skip_source_norms)?;
    // waybar generation moved to Home Manager in Phase 4.
    generate::generate_private_files_to(&shadow_paths, private_cfg)?;

    // Compare generated files
    let mut diffs: BTreeMap<String, String> = BTreeMap::new();

    fn compare_files(
        real: &std::path::Path,
        shadow: &std::path::Path,
        rel: &str,
        diffs: &mut BTreeMap<String, String>,
    ) {
        match (std::fs::read(real), std::fs::read(shadow)) {
            (Ok(a), Ok(b)) if a == b => {}
            (Ok(a), Ok(b)) => {
                diffs.insert(
                    rel.to_string(),
                    format!("content differs ({} bytes vs {} bytes)", a.len(), b.len()),
                );
            }
            (Err(_), Ok(_)) => {
                diffs.insert(rel.to_string(), "missing in current output".to_string());
            }
            (Ok(_), Err(_)) => {
                diffs.insert(rel.to_string(), "not generated by new code".to_string());
            }
            (Err(_), Err(_)) => {}
        }
    }

    let generated_files = [
        "goto/config.yml",
        "task/config.toml",
        "aerospace.toml",
        "cargo-config.toml",
        "alacritty.toml",
    ];

    for rel in &generated_files {
        compare_files(
            &paths.dist.join(rel),
            &shadow_build.join(rel),
            rel,
            &mut diffs,
        );
    }

    // (Phase 3 dropped the per-symlink comparator that compared
    // opencode/commands, /skills, /agents, /plugins. HM owns those now.)

    // Note: opencode commands/skills/agents/plugins comparisons were
    // dropped in Phase 3; HM owns those merges now.

    // Cleanup
    let _ = std::fs::remove_dir_all(&temp_dir);

    if diffs.is_empty() {
        println!("check: all generated files match");
        Ok(())
    } else {
        println!("check: {} file(s) differ:", diffs.len());
        for (file, reason) in &diffs {
            println!("  {file}: {reason}");
        }
        std::process::exit(1);
    }
}

fn log(msg: &str) {
    println!("==> {msg}");
}

fn warn(msg: &str) {
    eprintln!("warning: {msg}");
}
