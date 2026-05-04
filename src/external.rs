use std::{path::Path, process::Command};

use anyhow::{Context, Result};

use crate::config::Paths;

/// Legacy per-domain Nix profile names installed by previous setup-tool
/// versions. Removed once on first Phase 2 run so they don't shadow the
/// Home Manager generation in `~/.nix-profile`.
const LEGACY_NIX_PROFILES: &[&str] = &[
    "desktop",
    "editors",
    "fs",
    "git",
    "helix-langs",
    "helix-plugins",
    "rust",
    "shell",
    "toolchain",
];

/// Build and activate the Home Manager generation defined in the
/// dotfiles flake. Replaces the per-flake `nix profile add` loop.
pub fn install_home_manager(paths: &Paths) -> Result<()> {
    if !command_exists("nix") {
        crate::warn("nix not found. Install Nix first to use the dotfiles flake.");
        return Ok(());
    }

    let host = detect_host()?;
    let flake_ref = format!(
        "path:{}#homeConfigurations.{host}.activationPackage",
        paths.dotfiles.display()
    );

    crate::log(&format!("Building home-manager generation for {host}"));

    let nvidia_driver_version = nvidia_driver_version();

    let mut build = Command::new("nix");
    build.args([
        "--extra-experimental-features",
        "nix-command flakes",
        "build",
        "--impure",
        "--no-link",
        "--print-out-paths",
        &flake_ref,
    ]);
    if let Some(version) = nvidia_driver_version.as_deref() {
        build.env("NIXGL_NVIDIA_VERSION", version);
    }

    let build_output = build.output().context("running nix build for home-manager")?;
    if !build_output.status.success() {
        let stderr = String::from_utf8_lossy(&build_output.stderr);
        crate::warn(&format!(
            "nix build failed for home-manager#{host}; leaving profile unchanged\n{stderr}"
        ));
        return Ok(());
    }

    let out_path = String::from_utf8(build_output.stdout)
        .context("decoding nix build stdout")?
        .trim()
        .to_string();
    if out_path.is_empty() {
        crate::warn("nix build produced no output path for home-manager");
        return Ok(());
    }

    cleanup_legacy_profiles();

    let activate_script = Path::new(&out_path).join("activate");
    crate::log(&format!(
        "Activating home-manager generation: {}",
        activate_script.display()
    ));

    let mut activate = Command::new(&activate_script);
    if let Some(version) = nvidia_driver_version.as_deref() {
        activate.env("NIXGL_NVIDIA_VERSION", version);
    }
    let activate_status = activate.status().context("running activation script")?;
    if !activate_status.success() {
        crate::warn("home-manager activation failed");
    }

    Ok(())
}

/// Determine the homeConfigurations attribute name for the current host.
/// `DOTFILES_HOST` overrides the platform default.
fn detect_host() -> Result<String> {
    if let Ok(value) = std::env::var("DOTFILES_HOST") {
        if !value.is_empty() {
            return Ok(value);
        }
    }
    Ok(match std::env::consts::OS {
        "macos" => "thomas-darwin".into(),
        "linux" => "thomas-linux".into(),
        other => anyhow::bail!("unsupported OS for dotfiles: {other}"),
    })
}

/// Best-effort removal of legacy per-domain Nix profiles. Errors are
/// swallowed because the profile may already be absent on a fresh
/// machine.
fn cleanup_legacy_profiles() {
    for name in LEGACY_NIX_PROFILES {
        let _ = Command::new("nix")
            .args([
                "--extra-experimental-features",
                "nix-command flakes",
                "profile",
                "remove",
                name,
            ])
            .output();
    }
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

fn nvidia_driver_version() -> Option<String> {
    let output = Command::new("nvidia-smi")
        .args(["--query-gpu=driver_version", "--format=csv,noheader"])
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    String::from_utf8(output.stdout)
        .ok()?
        .lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(str::to_owned)
}
