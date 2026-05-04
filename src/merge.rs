use std::path::Path;

use anyhow::{Context, Result};

use crate::{config, config::Paths, link};

// ── Generic overlay-append merges ───────────────────────────────────────
//
// AeroSpace, Cargo, Alacritty, and task each use a "base file + sorted
// overlays" pattern. The overlay-append helpers below back all four.
// Phases 5 and 6 will retire these in favour of HM modules.

/// Collect overlay files matching a prefix+extension in a directory, sorted by filename bytes.
/// Optionally excludes a specific path (e.g. the base file itself).
fn collect_overlays_from(
    dir: &Path,
    prefix: &str,
    extension: &str,
) -> Result<Vec<std::path::PathBuf>> {
    if !dir.is_dir() {
        return Ok(Vec::new());
    }

    let mut overlays: Vec<std::path::PathBuf> = std::fs::read_dir(dir)?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            let name = p.file_name().unwrap_or_default().to_string_lossy();
            name.starts_with(prefix)
                && name.ends_with(extension)
                && p.is_file()
                && p.metadata().map(|m| m.len() > 0).unwrap_or(false)
        })
        .collect();

    // LC_ALL=C byte-order sort
    overlays.sort_by(|a, b| {
        a.file_name()
            .unwrap_or_default()
            .as_encoded_bytes()
            .cmp(b.file_name().unwrap_or_default().as_encoded_bytes())
    });

    Ok(overlays)
}

/// Collect overlay files from the private config directory (backward-compatible name).
fn collect_overlays(
    dotfiles_config: &Path,
    prefix: &str,
    extension: &str,
) -> Result<Vec<std::path::PathBuf>> {
    collect_overlays_from(dotfiles_config, prefix, extension)
}

/// Merge a base config file with overlay files by appending.
/// Source paths under `dotfiles_root` are filtered through `skip_source_norms`.
fn merge_overlay(
    base_path: &Path,
    merged_path: &Path,
    overlays: &[std::path::PathBuf],
    dotfiles_root: &Path,
    skip_source_norms: &[String],
) -> Result<()> {
    std::fs::create_dir_all(merged_path.parent().unwrap())?;

    let mut content = std::fs::read_to_string(base_path)
        .with_context(|| format!("reading {}", base_path.display()))?;

    for overlay in overlays {
        if config::should_skip_source(overlay, dotfiles_root, skip_source_norms) {
            continue;
        }
        // Check readable
        let overlay_content = match std::fs::read_to_string(overlay) {
            Ok(c) => c,
            Err(_) => continue,
        };
        content.push('\n');
        content.push_str(&overlay_content);
    }

    std::fs::write(merged_path, &content)?;
    Ok(())
}

// ── AeroSpace ───────────────────────────────────────────────────────────

pub fn merge_aerospace(
    paths: &Paths,
    skip_norms: &[String],
    skip_source_norms: &[String],
) -> Result<()> {
    let dest_link = paths.home.join(".aerospace.toml");
    if config::should_skip_dest(&dest_link, &paths.home, skip_norms) {
        crate::log(&format!("Skipping {}", dest_link.display()));
        link::remove_managed_link_if_present(&dest_link, paths)?;
        return Ok(());
    }

    let base = paths.dotfiles.join("config/aerospace/aerospace.toml");
    if !base.exists() {
        crate::warn(&format!(
            "aerospace base config not found at {}",
            base.display()
        ));
        return Ok(());
    }

    let merged_path = merge_aerospace_to(paths, skip_source_norms)?;
    link::force_symlink(&merged_path, &dest_link)
}

pub fn merge_aerospace_to(
    paths: &Paths,
    skip_source_norms: &[String],
) -> Result<std::path::PathBuf> {
    let base = paths.dotfiles.join("config/aerospace/aerospace.toml");
    let merged_path = paths.dist.join("aerospace.toml");
    let mut overlays = collect_overlays_from(
        &paths.dotfiles.join("config/aerospace"),
        "aerospace.",
        ".toml",
    )?;
    overlays.retain(|p| p != &base);
    overlays.extend(collect_overlays(
        &paths.dotfiles_config,
        "aerospace.",
        ".toml",
    )?);
    merge_overlay(
        &base,
        &merged_path,
        &overlays,
        &paths.dotfiles,
        skip_source_norms,
    )?;
    Ok(merged_path)
}

// ── Cargo ───────────────────────────────────────────────────────────────

pub fn merge_cargo(
    paths: &Paths,
    skip_norms: &[String],
    skip_source_norms: &[String],
) -> Result<()> {
    let dest_link = paths.home.join(".cargo/config.toml");
    if config::should_skip_dest(&dest_link, &paths.home, skip_norms) {
        crate::log(&format!("Skipping {}", dest_link.display()));
        link::remove_managed_link_if_present(&dest_link, paths)?;
        return Ok(());
    }

    let base = paths.dotfiles.join("config/cargo/cargo-config.toml");
    if !base.exists() {
        crate::warn(&format!(
            "cargo base config not found at {}",
            base.display()
        ));
        return Ok(());
    }

    let merged_path = merge_cargo_to(paths, skip_source_norms)?;

    // Ensure ~/.cargo/ exists
    std::fs::create_dir_all(dest_link.parent().unwrap())?;
    link::force_symlink(&merged_path, &dest_link)
}

pub fn merge_cargo_to(paths: &Paths, skip_source_norms: &[String]) -> Result<std::path::PathBuf> {
    let base = paths.dotfiles.join("config/cargo/cargo-config.toml");
    let merged_path = paths.dist.join("cargo-config.toml");
    // Repo-level overlays first (e.g. config/cargo/cargo.darwin.toml), then private overlays
    let mut overlays =
        collect_overlays_from(&paths.dotfiles.join("config/cargo"), "cargo.", ".toml")?;
    overlays.extend(collect_overlays(&paths.dotfiles_config, "cargo.", ".toml")?);
    merge_overlay(
        &base,
        &merged_path,
        &overlays,
        &paths.dotfiles,
        skip_source_norms,
    )?;
    Ok(merged_path)
}

// ── Task ────────────────────────────────────────────────────────────────

pub fn merge_task(
    paths: &Paths,
    skip_norms: &[String],
    skip_source_norms: &[String],
) -> Result<()> {
    let dest_link = paths.home.join(".config/task/config.toml");
    if config::should_skip_dest(&dest_link, &paths.home, skip_norms) {
        crate::log(&format!("Skipping {}", dest_link.display()));
        link::remove_managed_link_if_present(&dest_link, paths)?;
        return Ok(());
    }

    let base = paths.dotfiles.join("config/task/config.toml");
    if !base.exists() {
        crate::warn(&format!("task base config not found at {}", base.display()));
        return Ok(());
    }

    let merged_path = merge_task_to(paths, skip_source_norms)?;

    std::fs::create_dir_all(dest_link.parent().unwrap())?;
    link::force_symlink(&merged_path, &dest_link)
}

pub fn merge_task_to(paths: &Paths, skip_source_norms: &[String]) -> Result<std::path::PathBuf> {
    let base = paths.dotfiles.join("config/task/config.toml");
    let merged_path = paths.dist.join("task/config.toml");
    // Repo-level overlays first (e.g. config/task/task.darwin.toml), then private overlays
    let mut overlays =
        collect_overlays_from(&paths.dotfiles.join("config/task"), "task.", ".toml")?;
    overlays.retain(|p| p != &base);
    overlays.extend(collect_overlays(&paths.dotfiles_config, "task.", ".toml")?);
    merge_overlay(
        &base,
        &merged_path,
        &overlays,
        &paths.dotfiles,
        skip_source_norms,
    )?;
    Ok(merged_path)
}

// ── Alacritty ───────────────────────────────────────────────────────────

pub fn merge_alacritty(
    paths: &Paths,
    skip_norms: &[String],
    skip_source_norms: &[String],
) -> Result<()> {
    let dest_link = paths.home.join(".config/alacritty/alacritty.toml");
    if config::should_skip_dest(&dest_link, &paths.home, skip_norms) {
        crate::log(&format!("Skipping {}", dest_link.display()));
        link::remove_managed_link_if_present(&dest_link, paths)?;
        return Ok(());
    }

    let base = paths.dotfiles.join("config/alacritty/alacritty.toml");
    if !base.exists() {
        crate::warn(&format!(
            "alacritty base config not found at {}",
            base.display()
        ));
        return Ok(());
    }

    let merged_path = merge_alacritty_to(paths, skip_source_norms)?;

    std::fs::create_dir_all(dest_link.parent().unwrap())?;
    link::force_symlink(&merged_path, &dest_link)?;

    // Link themes submodule so the import path resolves
    let themes_src = paths.dotfiles.join("config/alacritty/themes");
    let themes_dest = paths.home.join(".config/alacritty/themes");
    if themes_src.is_dir() {
        link::force_symlink(&themes_src, &themes_dest)?;
    }

    Ok(())
}

pub fn merge_alacritty_to(
    paths: &Paths,
    skip_source_norms: &[String],
) -> Result<std::path::PathBuf> {
    let base = paths.dotfiles.join("config/alacritty/alacritty.toml");
    let merged_path = paths.dist.join("alacritty.toml");
    let mut overlays = collect_overlays_from(
        &paths.dotfiles.join("config/alacritty"),
        "alacritty.",
        ".toml",
    )?;
    overlays.retain(|p| p != &base);
    overlays.extend(collect_overlays(
        &paths.dotfiles_config,
        "alacritty.",
        ".toml",
    )?);
    merge_overlay(
        &base,
        &merged_path,
        &overlays,
        &paths.dotfiles,
        skip_source_norms,
    )?;
    Ok(merged_path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn merge_overlay_includes_all_when_no_skip() {
        let dir = std::env::temp_dir().join("dotfiles-test-merge-overlay-noskip");
        let _ = std::fs::remove_dir_all(&dir);
        let dotfiles = dir.join("dotfiles");
        std::fs::create_dir_all(dotfiles.join("config/cargo")).unwrap();

        std::fs::write(dotfiles.join("config/cargo/base.toml"), "[base]\nkey = 1\n").unwrap();
        std::fs::write(
            dotfiles.join("config/cargo/cargo.darwin.toml"),
            "[env]\nCC = \"clang\"\n",
        )
        .unwrap();

        let merged = dir.join("merged.toml");
        let overlays = vec![dotfiles.join("config/cargo/cargo.darwin.toml")];
        merge_overlay(
            &dotfiles.join("config/cargo/base.toml"),
            &merged,
            &overlays,
            &dotfiles,
            &[],
        )
        .unwrap();

        let content = std::fs::read_to_string(&merged).unwrap();
        assert!(content.contains("[base]"));
        assert!(content.contains("[env]"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn merge_overlay_skips_source() {
        let dir = std::env::temp_dir().join("dotfiles-test-merge-overlay-skip");
        let _ = std::fs::remove_dir_all(&dir);
        let dotfiles = dir.join("dotfiles");
        std::fs::create_dir_all(dotfiles.join("config/cargo")).unwrap();

        std::fs::write(dotfiles.join("config/cargo/base.toml"), "[base]\nkey = 1\n").unwrap();
        std::fs::write(
            dotfiles.join("config/cargo/cargo.darwin.toml"),
            "[env]\nCC = \"clang\"\n",
        )
        .unwrap();

        let merged = dir.join("merged.toml");
        let overlays = vec![dotfiles.join("config/cargo/cargo.darwin.toml")];
        let skip = vec!["config/cargo/cargo.darwin.toml".to_string()];
        merge_overlay(
            &dotfiles.join("config/cargo/base.toml"),
            &merged,
            &overlays,
            &dotfiles,
            &skip,
        )
        .unwrap();

        let content = std::fs::read_to_string(&merged).unwrap();
        assert!(content.contains("[base]"));
        assert!(
            !content.contains("[env]"),
            "skipped overlay should not appear"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn merge_overlay_skips_only_matching_source() {
        let dir = std::env::temp_dir().join("dotfiles-test-merge-overlay-partial");
        let _ = std::fs::remove_dir_all(&dir);
        let dotfiles = dir.join("dotfiles");
        std::fs::create_dir_all(dotfiles.join("config/cargo")).unwrap();

        std::fs::write(dotfiles.join("config/cargo/base.toml"), "[base]\n").unwrap();
        std::fs::write(
            dotfiles.join("config/cargo/cargo.darwin.toml"),
            "[darwin]\n",
        )
        .unwrap();
        std::fs::write(dotfiles.join("config/cargo/cargo.linux.toml"), "[linux]\n").unwrap();

        let merged = dir.join("merged.toml");
        let overlays = vec![
            dotfiles.join("config/cargo/cargo.darwin.toml"),
            dotfiles.join("config/cargo/cargo.linux.toml"),
        ];
        let skip = vec!["config/cargo/cargo.darwin.toml".to_string()];
        merge_overlay(
            &dotfiles.join("config/cargo/base.toml"),
            &merged,
            &overlays,
            &dotfiles,
            &skip,
        )
        .unwrap();

        let content = std::fs::read_to_string(&merged).unwrap();
        assert!(content.contains("[base]"));
        assert!(!content.contains("[darwin]"));
        assert!(content.contains("[linux]"));

        let _ = std::fs::remove_dir_all(&dir);
    }
}
