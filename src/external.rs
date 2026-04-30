use std::{path::Path, process::Command};

use anyhow::{Context, Result};

use crate::config::Paths;

/// Install the Nix toolchain from the dotfiles flake.
pub fn install_nix_toolchain(paths: &Paths) -> Result<()> {
    install_nix_profile(paths, "toolchain")
}

/// Install Helix language tooling from the dotfiles flake.
pub fn install_helix_language_tools(paths: &Paths) -> Result<()> {
    install_nix_profile(paths, "helix-langs")
}

/// Install the Steel-enabled Helix package with pinned plugins.
pub fn install_helix_plugins(paths: &Paths) -> Result<()> {
    install_nix_profile(paths, "helix-plugins")
}

fn install_nix_profile(paths: &Paths, name: &str) -> Result<()> {
    if !command_exists("nix") {
        crate::warn("nix not found. Install Nix first to use the flake toolchain.");
        return Ok(());
    }

    let flake_dir = paths.dotfiles.join("config/nix/flakes").join(name);
    let flake_ref = format!("path:{}#{name}", flake_dir.display());

    crate::log(&format!(
        "Installing Nix profile {name} from {}",
        flake_dir.display()
    ));

    let build_status = Command::new("nix")
        .args([
            "--extra-experimental-features",
            "nix-command flakes",
            "build",
            "--no-link",
            &flake_ref,
        ])
        .status()
        .context("running nix build")?;

    if !build_status.success() {
        crate::warn(&format!(
            "nix build failed for {name}; leaving profile unchanged"
        ));
        return Ok(());
    }

    let _ = Command::new("nix")
        .args([
            "--extra-experimental-features",
            "nix-command flakes",
            "profile",
            "remove",
            name,
        ])
        .output();

    let status = Command::new("nix")
        .args([
            "--extra-experimental-features",
            "nix-command flakes",
            "profile",
            "add",
            &flake_ref,
        ])
        .status()
        .context("running nix profile add")?;

    if !status.success() {
        crate::warn(&format!("nix profile add failed for {name}"));
    }

    Ok(())
}

/// Run `task bootstrap` if the task binary is available.
pub fn run_task_bootstrap(home: &Path) -> Result<()> {
    let task_bin = home.join(".cargo/bin/task");
    if !task_bin.exists() {
        crate::warn("task not found");
        return Ok(());
    }

    crate::log("Running task bootstrap");
    let status = Command::new(&task_bin)
        .args(["bootstrap", "--yes"])
        .status()
        .context("running task bootstrap")?;

    if !status.success() {
        crate::warn("task bootstrap failed");
    }

    Ok(())
}

fn command_exists(name: &str) -> bool {
    Command::new("which")
        .arg(name)
        .output()
        .map(|o| o.status.success())
        .unwrap_or(false)
}
