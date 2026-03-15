use std::{path::Path, process::Command};

use anyhow::{Context, Result};

use crate::config::Paths;

/// Install the Nix toolchain from the dotfiles flake.
pub fn install_nix_toolchain(paths: &Paths) -> Result<()> {
    if !command_exists("nix") {
        crate::warn("nix not found. Install Nix first to use the flake toolchain.");
        return Ok(());
    }

    let flake_ref = format!(
        "path:{}#toolchain",
        paths.dotfiles.join("home/flakes/toolchain").display()
    );

    crate::log(&format!(
        "Installing Nix toolchain from {}/home/flakes/toolchain",
        paths.dotfiles.display()
    ));

    // Remove old profile entry (ignore failure)
    let _ = Command::new("nix")
        .args([
            "--extra-experimental-features",
            "nix-command flakes",
            "profile",
            "remove",
            "toolchain",
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
        crate::warn("nix profile add failed");
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
        .args(["bootstrap"])
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
