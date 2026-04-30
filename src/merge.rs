use std::path::Path;

use anyhow::{Context, Result};

use crate::{
    config::{self, Paths, RulesMode},
    link,
};

// ── opencode.json deep merge ────────────────────────────────────────────

/// Deep-merge two JSON values. Base keys come first, then new overlay keys.
/// For objects: merge recursively, overlay wins for non-object conflicts.
/// For everything else: overlay wins.
fn deep_merge_json(base: serde_json::Value, overlay: serde_json::Value) -> serde_json::Value {
    use serde_json::Value;

    match (base, overlay) {
        (Value::Object(base_map), Value::Object(overlay_map)) => {
            let mut result = serde_json::Map::new();

            // Insert base keys first (preserving base order)
            for (key, base_val) in base_map {
                if let Some(overlay_val) = overlay_map.get(&key) {
                    result.insert(key, deep_merge_json(base_val, overlay_val.clone()));
                } else {
                    result.insert(key, base_val);
                }
            }

            // Then insert overlay-only keys (preserving overlay order)
            for (key, val) in overlay_map {
                if !result.contains_key(&key) {
                    result.insert(key, val);
                }
            }

            Value::Object(result)
        }
        (_base, overlay) => overlay,
    }
}

pub fn merge_opencode_json(
    paths: &Paths,
    skip_norms: &[String],
    skip_source_norms: &[String],
) -> Result<()> {
    let dest_link = paths.home.join(".config/opencode/opencode.json");
    if config::should_skip_dest(&dest_link, &paths.home, skip_norms) {
        crate::log(&format!("Skipping {}", dest_link.display()));
        link::remove_managed_link_if_present(&dest_link, paths)?;
        return Ok(());
    }

    let merged_path = merge_opencode_json_to(paths, skip_source_norms)?;
    link::force_symlink(&merged_path, &dest_link)
}

/// Generate merged opencode.json into dist, returning the path.
///
/// Merge order (each layer wins over the previous):
///   1. Public base (`config/opencode/opencode.json`)
///   2. Repo-level JSON fragments (`config/opencode/opencode.*.json`, LC_ALL=C sorted)
///   3. Private JSON fragments (`~/.config/dotfiles/opencode/opencode.*.json`, LC_ALL=C sorted)
///   4. Private overlay (`~/.config/dotfiles/opencode/opencode.json`)
pub fn merge_opencode_json_to(
    paths: &Paths,
    skip_source_norms: &[String],
) -> Result<std::path::PathBuf> {
    let public_config = paths.dotfiles.join("config/opencode/opencode.json");
    let merged_path = paths.dist.join("opencode/opencode.json");
    std::fs::create_dir_all(merged_path.parent().unwrap())?;

    let public_content = std::fs::read_to_string(&public_config)
        .with_context(|| format!("reading {}", public_config.display()))?;
    let public_json: serde_json::Value = serde_json::from_str(&public_content)
        .with_context(|| format!("parsing {}", public_config.display()))?;

    let mut merged = public_json;

    // Collect repo-level fragments (opencode.*.json next to the base), excluding the base itself
    let mut fragments = collect_overlays_from(
        &paths.dotfiles.join("config/opencode"),
        "opencode.",
        ".json",
    )?;
    fragments.retain(|p| p != &public_config);

    // Collect private fragments (opencode.*.json next to the private overlay), excluding it
    let private_dir = paths
        .opencode_json
        .parent()
        .expect("opencode_json has a parent dir");
    let mut private_fragments = collect_overlays_from(private_dir, "opencode.", ".json")?;
    private_fragments.retain(|p| p != &paths.opencode_json);
    fragments.extend(private_fragments);

    // Apply fragments in sorted order, respecting skip_sources
    for frag_path in &fragments {
        if config::should_skip_source(frag_path, &paths.dotfiles, skip_source_norms) {
            continue;
        }
        let frag_content = std::fs::read_to_string(frag_path)
            .with_context(|| format!("reading fragment {}", frag_path.display()))?;
        let frag_json: serde_json::Value = serde_json::from_str(&frag_content)
            .with_context(|| format!("parsing fragment {}", frag_path.display()))?;
        merged = deep_merge_json(merged, frag_json);
    }

    // Apply private overlay last (wins over all fragments)
    if paths.opencode_json.exists() {
        let private_content = std::fs::read_to_string(&paths.opencode_json)
            .with_context(|| format!("reading {}", paths.opencode_json.display()))?;
        let private_json: serde_json::Value = serde_json::from_str(&private_content)
            .with_context(|| format!("parsing {}", paths.opencode_json.display()))?;
        merged = deep_merge_json(merged, private_json);
    }

    let mut output =
        serde_json::to_string_pretty(&merged).context("serializing merged opencode.json")?;
    output.push('\n');
    std::fs::write(&merged_path, &output)?;

    Ok(merged_path)
}

// ── AGENTS.md merge ─────────────────────────────────────────────────────

pub fn merge_rules(paths: &Paths, skip_norms: &[String], mode: RulesMode) -> Result<()> {
    let dest_link = paths.home.join(".config/opencode/AGENTS.md");

    if config::should_skip_dest(&dest_link, &paths.home, skip_norms) || mode == RulesMode::Disabled
    {
        if mode != RulesMode::Disabled {
            crate::log(&format!("Skipping {}", dest_link.display()));
        }
        link::remove_managed_link_if_present(&dest_link, paths)?;
        return Ok(());
    }

    let merged_path = merge_rules_to(paths, mode)?;
    link::force_symlink(&merged_path, &dest_link)
}

/// Generate merged AGENTS.md into dist, returning the path.
pub fn merge_rules_to(paths: &Paths, mode: RulesMode) -> Result<std::path::PathBuf> {
    let merged_path = paths.dist.join("opencode/AGENTS.md");
    std::fs::create_dir_all(merged_path.parent().unwrap())?;

    let mut content = if mode == RulesMode::Merged {
        std::fs::read_to_string(paths.dotfiles.join("config/opencode/AGENTS.md"))
            .context("reading public AGENTS.md")?
    } else {
        String::new()
    };

    let mut appended_any = false;

    if paths.opencode_rules.is_dir() {
        let mut overlay_files: Vec<_> = std::fs::read_dir(&paths.opencode_rules)
            .with_context(|| format!("reading {}", paths.opencode_rules.display()))?
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .collect();

        // LC_ALL=C sort: sort by raw bytes of filename
        overlay_files.sort_by(|a, b| {
            a.file_name()
                .unwrap_or_default()
                .as_encoded_bytes()
                .cmp(b.file_name().unwrap_or_default().as_encoded_bytes())
        });

        for overlay_path in &overlay_files {
            if !overlay_path.is_file() {
                continue;
            }

            let meta = match overlay_path.metadata() {
                Ok(m) => m,
                Err(_) => {
                    crate::warn(&format!(
                        "rules overlay is not readable: {}",
                        overlay_path.display()
                    ));
                    continue;
                }
            };

            // Skip empty files
            if meta.len() == 0 {
                continue;
            }

            // Check readable by attempting to read
            let overlay_content = match std::fs::read_to_string(overlay_path) {
                Ok(c) => c,
                Err(_) => {
                    crate::warn(&format!(
                        "rules overlay is not readable: {}",
                        overlay_path.display()
                    ));
                    continue;
                }
            };

            if !content.is_empty() {
                content.push_str("\n\n");
            }

            let filename = overlay_path
                .file_name()
                .unwrap_or_default()
                .to_string_lossy();
            content.push_str(&format!("# Rules overlay: {}\n\n", filename));
            content.push_str(&overlay_content);
            appended_any = true;
        }
    }

    if mode == RulesMode::PrivateOnly && !appended_any {
        crate::warn(&format!(
            "rules_mode=private_only but no readable non-empty files found in {}",
            paths.opencode_rules.display()
        ));
    }

    // Replace __DOTFILES_PATH__ placeholder
    content = content.replace("__DOTFILES_PATH__", &paths.dotfiles.to_string_lossy());

    std::fs::write(&merged_path, &content)?;
    Ok(merged_path)
}

// ── OpenCode directory merges (commands, skills, agents, plugins) ────────

#[derive(Clone, Copy)]
enum MergeStyle {
    /// Symlink individual files (commands, agents, plugins)
    FlatFiles,
    /// Symlink subdirectories with trailing slash (skills)
    Subdirectories,
}

struct MergedDir {
    name: &'static str,
    style: MergeStyle,
}

/// Declarative list of OpenCode directories that are merged from
/// public (`config/opencode/{name}`) and private (`~/.config/dotfiles/opencode/{name}`)
/// sources into `~/.local/share/dotfiles/opencode/{name}`.
const MERGED_DIRS: &[MergedDir] = &[
    MergedDir {
        name: "commands",
        style: MergeStyle::FlatFiles,
    },
    MergedDir {
        name: "skills",
        style: MergeStyle::Subdirectories,
    },
    MergedDir {
        name: "agents",
        style: MergeStyle::FlatFiles,
    },
    MergedDir {
        name: "plugins",
        style: MergeStyle::FlatFiles,
    },
];

/// Merge and link all OpenCode directories listed in MERGED_DIRS.
pub fn merge_all_dirs(paths: &Paths, skip_norms: &[String]) -> Result<()> {
    for spec in MERGED_DIRS {
        let dest_link = paths.home.join(format!(".config/opencode/{}", spec.name));
        if config::should_skip_dest(&dest_link, &paths.home, skip_norms) {
            crate::log(&format!("Skipping {}", dest_link.display()));
            link::remove_managed_link_if_present(&dest_link, paths)?;
            continue;
        }
        let merge_dir = merge_dir_to(paths, spec)?;
        link::force_symlink(&merge_dir, &dest_link)?;
    }
    Ok(())
}

/// Generate all merged OpenCode directories into dist (for --check).
pub fn merge_all_dirs_to(paths: &Paths) -> Result<()> {
    for spec in MERGED_DIRS {
        merge_dir_to(paths, spec)?;
    }
    Ok(())
}

fn merge_dir_to(paths: &Paths, spec: &MergedDir) -> Result<std::path::PathBuf> {
    let merge_dir = paths.dist.join(format!("opencode/{}", spec.name));
    let public_dir = paths
        .dotfiles
        .join(format!("config/opencode/{}", spec.name));
    let private_dir = paths
        .dotfiles_config
        .join(format!("opencode/{}", spec.name));

    if merge_dir.exists() {
        std::fs::remove_dir_all(&merge_dir)?;
    }
    std::fs::create_dir_all(&merge_dir)?;

    match spec.style {
        MergeStyle::FlatFiles => {
            link_flat_files(&public_dir, &merge_dir)?;
            link_flat_files(&private_dir, &merge_dir)?;
        }
        MergeStyle::Subdirectories => {
            link_subdirs(&public_dir, &merge_dir)?;
            link_subdirs(&private_dir, &merge_dir)?;
        }
    }

    Ok(merge_dir)
}

// ── package.json deep merge ────────────────────────────────────────────

pub fn merge_opencode_package_json(paths: &Paths, skip_norms: &[String]) -> Result<()> {
    let dest_link = paths.home.join(".config/opencode/package.json");
    if config::should_skip_dest(&dest_link, &paths.home, skip_norms) {
        crate::log(&format!("Skipping {}", dest_link.display()));
        link::remove_managed_link_if_present(&dest_link, paths)?;
        return Ok(());
    }

    let merged_path = merge_opencode_package_json_to(paths)?;
    // Only link if a merged file was actually produced
    if let Some(path) = merged_path {
        link::force_symlink(&path, &dest_link)
    } else {
        link::remove_managed_link_if_present(&dest_link, paths)?;
        Ok(())
    }
}

/// Generate merged package.json into dist, returning the path if any source exists.
///
/// Merge order (each layer wins over the previous):
///   1. Public base (`config/opencode/package.json`)
///   2. Private overlay (`~/.config/dotfiles/opencode/package.json`)
pub fn merge_opencode_package_json_to(paths: &Paths) -> Result<Option<std::path::PathBuf>> {
    let public_config = paths.dotfiles.join("config/opencode/package.json");
    let merged_path = paths.dist.join("opencode/package.json");
    std::fs::create_dir_all(merged_path.parent().unwrap())?;

    let has_public = public_config.exists();
    let has_private = paths.opencode_package_json.exists();

    if !has_public && !has_private {
        // No package.json sources at all — clean up stale output
        let _ = std::fs::remove_file(&merged_path);
        return Ok(None);
    }

    let mut merged: serde_json::Value = if has_public {
        let content = std::fs::read_to_string(&public_config)
            .with_context(|| format!("reading {}", public_config.display()))?;
        serde_json::from_str(&content)
            .with_context(|| format!("parsing {}", public_config.display()))?
    } else {
        serde_json::Value::Object(serde_json::Map::new())
    };

    if has_private {
        let content = std::fs::read_to_string(&paths.opencode_package_json)
            .with_context(|| format!("reading {}", paths.opencode_package_json.display()))?;
        let private_json: serde_json::Value = serde_json::from_str(&content)
            .with_context(|| format!("parsing {}", paths.opencode_package_json.display()))?;
        merged = deep_merge_json(merged, private_json);
    }

    let mut output =
        serde_json::to_string_pretty(&merged).context("serializing merged package.json")?;
    output.push('\n');
    std::fs::write(&merged_path, &output)?;

    Ok(Some(merged_path))
}

/// Append a trailing `/` to a path, matching bash glob `*/` behavior.
fn append_slash(p: &Path) -> std::ffi::OsString {
    let mut s = p.as_os_str().to_os_string();
    s.push("/");
    s
}

fn link_flat_files(src_dir: &Path, merge_dir: &Path) -> Result<()> {
    if !src_dir.is_dir() {
        return Ok(());
    }
    for entry in std::fs::read_dir(src_dir)? {
        let entry = entry?;
        if entry.path().is_file() {
            link::force_symlink(&entry.path(), &merge_dir.join(entry.file_name()))?;
        }
    }
    Ok(())
}

fn link_subdirs(src_dir: &Path, merge_dir: &Path) -> Result<()> {
    if !src_dir.is_dir() {
        return Ok(());
    }
    for entry in std::fs::read_dir(src_dir)? {
        let entry = entry?;
        if entry.path().is_dir() {
            let src = append_slash(&entry.path());
            link::force_symlink(Path::new(&src), &merge_dir.join(entry.file_name()))?;
        }
    }
    Ok(())
}

// ── Generic overlay-append merges ───────────────────────────────────────

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
    fn deep_merge_preserves_base_key_order() {
        let base: serde_json::Value = serde_json::json!({
            "z_key": 1,
            "a_key": 2,
            "m_key": 3
        });
        let overlay: serde_json::Value = serde_json::json!({
            "a_key": 99
        });
        let merged = deep_merge_json(base, overlay);
        let keys: Vec<&String> = merged.as_object().unwrap().keys().collect();
        assert_eq!(keys, vec!["z_key", "a_key", "m_key"]);
        assert_eq!(merged["a_key"], 99);
    }

    #[test]
    fn deep_merge_adds_overlay_keys_at_end() {
        let base: serde_json::Value = serde_json::json!({
            "existing": 1
        });
        let overlay: serde_json::Value = serde_json::json!({
            "existing": 2,
            "new_key": 3
        });
        let merged = deep_merge_json(base, overlay);
        let keys: Vec<&String> = merged.as_object().unwrap().keys().collect();
        assert_eq!(keys, vec!["existing", "new_key"]);
        assert_eq!(merged["existing"], 2);
    }

    #[test]
    fn deep_merge_recursive() {
        let base: serde_json::Value = serde_json::json!({
            "command": {
                "task-plan": { "description": "old" },
                "task-check": { "description": "check" }
            }
        });
        let overlay: serde_json::Value = serde_json::json!({
            "command": {
                "task-plan": { "description": "new" },
                "new-cmd": { "description": "added" }
            }
        });
        let merged = deep_merge_json(base, overlay);
        assert_eq!(merged["command"]["task-plan"]["description"], "new");
        assert_eq!(merged["command"]["task-check"]["description"], "check");
        assert_eq!(merged["command"]["new-cmd"]["description"], "added");
    }

    #[test]
    fn deep_merge_array_replaced_not_merged() {
        let base: serde_json::Value = serde_json::json!({
            "items": [1, 2, 3]
        });
        let overlay: serde_json::Value = serde_json::json!({
            "items": [4, 5]
        });
        let merged = deep_merge_json(base, overlay);
        assert_eq!(merged["items"], serde_json::json!([4, 5]));
    }

    #[test]
    fn json_fragments_merged_in_order_private_overlay_wins() {
        let dir = std::env::temp_dir().join("dotfiles-test-json-fragments");
        let _ = std::fs::remove_dir_all(&dir);

        // Set up a fake dotfiles structure
        let dotfiles = dir.join("dotfiles");
        let public_opencode = dotfiles.join("config/opencode");
        std::fs::create_dir_all(&public_opencode).unwrap();

        // Public base
        std::fs::write(
            public_opencode.join("opencode.json"),
            r#"{"model": "base", "mcp": {"existing": {"type": "remote"}}}"#,
        )
        .unwrap();

        // Repo-level fragment
        std::fs::write(
            public_opencode.join("opencode.extra.json"),
            r#"{"mcp": {"from-fragment": {"type": "local", "command": ["frag"]}}}"#,
        )
        .unwrap();

        // Private config directory
        let private_dir = dir.join("private/opencode");
        std::fs::create_dir_all(&private_dir).unwrap();

        // Private fragment
        std::fs::write(
            private_dir.join("opencode.private-frag.json"),
            r#"{"mcp": {"private-tool": {"type": "local", "command": ["priv"]}}}"#,
        )
        .unwrap();

        // Private overlay (wins over all)
        std::fs::write(
            private_dir.join("opencode.json"),
            r#"{"model": "overlay-wins", "mcp": {"from-fragment": {"type": "local", "command": ["overridden"]}}}"#,
        )
        .unwrap();

        let paths = Paths {
            dotfiles: dotfiles.clone(),
            home: dir.join("home"),
            dev_root: dir.join("dev"),
            dotfiles_config: dir.join("private"),
            config_toml: dir.join("private/config.toml"),
            opencode_json: private_dir.join("opencode.json"),
            opencode_rules: private_dir.join("rules"),
            opencode_package_json: private_dir.join("package.json"),
            dist: dir.join("dist"),
        };

        std::fs::create_dir_all(&paths.dist).unwrap();

        let result_path = merge_opencode_json_to(&paths, &[]).unwrap();
        let content = std::fs::read_to_string(&result_path).unwrap();
        let json: serde_json::Value = serde_json::from_str(&content).unwrap();

        // Private overlay wins over base
        assert_eq!(json["model"], "overlay-wins");
        // Fragment-added key present
        assert!(json["mcp"]["private-tool"].is_object());
        // Fragment key overridden by private overlay
        assert_eq!(json["mcp"]["from-fragment"]["command"][0], "overridden");
        // Base MCP entry preserved
        assert!(json["mcp"]["existing"].is_object());

        let _ = std::fs::remove_dir_all(&dir);
    }

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

    fn test_paths(dir: &Path) -> Paths {
        let private_dir = dir.join("private/opencode");
        Paths {
            dotfiles: dir.join("dotfiles"),
            home: dir.join("home"),
            dev_root: dir.join("dev"),
            dotfiles_config: dir.join("private"),
            config_toml: dir.join("private/config.toml"),
            opencode_json: private_dir.join("opencode.json"),
            opencode_rules: private_dir.join("rules"),
            opencode_package_json: private_dir.join("package.json"),
            dist: dir.join("dist"),
        }
    }

    #[test]
    fn merge_dirs_links_public_files() {
        let dir = std::env::temp_dir().join("dotfiles-test-merge-dirs-public");
        let _ = std::fs::remove_dir_all(&dir);
        let paths = test_paths(&dir);

        let public_plugins = paths.dotfiles.join("config/opencode/plugins");
        let public_commands = paths.dotfiles.join("config/opencode/commands");
        std::fs::create_dir_all(&public_plugins).unwrap();
        std::fs::create_dir_all(&public_commands).unwrap();
        std::fs::write(public_plugins.join("my-plugin.ts"), "export const P = 1").unwrap();
        std::fs::write(
            public_commands.join("test.md"),
            "---\ndescription: Test\n---\nRun test",
        )
        .unwrap();
        std::fs::create_dir_all(&paths.dist).unwrap();

        merge_all_dirs_to(&paths).unwrap();

        let plugin_target =
            std::fs::read_link(paths.dist.join("opencode/plugins/my-plugin.ts")).unwrap();
        assert_eq!(plugin_target, public_plugins.join("my-plugin.ts"));

        let cmd_target = std::fs::read_link(paths.dist.join("opencode/commands/test.md")).unwrap();
        assert_eq!(cmd_target, public_commands.join("test.md"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn merge_dirs_private_overrides_public() {
        let dir = std::env::temp_dir().join("dotfiles-test-merge-dirs-override");
        let _ = std::fs::remove_dir_all(&dir);
        let paths = test_paths(&dir);

        let public_commands = paths.dotfiles.join("config/opencode/commands");
        let private_commands = paths.dotfiles_config.join("opencode/commands");
        std::fs::create_dir_all(&public_commands).unwrap();
        std::fs::write(public_commands.join("shared.md"), "public").unwrap();

        std::fs::create_dir_all(&private_commands).unwrap();
        std::fs::write(private_commands.join("shared.md"), "private").unwrap();
        std::fs::write(private_commands.join("private-only.md"), "priv").unwrap();

        let public_plugins = paths.dotfiles.join("config/opencode/plugins");
        let private_plugins = paths.dotfiles_config.join("opencode/plugins");
        std::fs::create_dir_all(&public_plugins).unwrap();
        std::fs::write(public_plugins.join("shared.ts"), "public").unwrap();

        std::fs::create_dir_all(&private_plugins).unwrap();
        std::fs::write(private_plugins.join("shared.ts"), "private").unwrap();
        std::fs::write(private_plugins.join("private-only.ts"), "priv").unwrap();

        std::fs::create_dir_all(&paths.dist).unwrap();

        merge_all_dirs_to(&paths).unwrap();

        // Commands: private wins on collision
        let shared_cmd =
            std::fs::read_link(paths.dist.join("opencode/commands/shared.md")).unwrap();
        assert_eq!(shared_cmd, private_commands.join("shared.md"));
        let priv_cmd =
            std::fs::read_link(paths.dist.join("opencode/commands/private-only.md")).unwrap();
        assert_eq!(priv_cmd, private_commands.join("private-only.md"));

        // Plugins: private wins on collision
        let shared_plug =
            std::fs::read_link(paths.dist.join("opencode/plugins/shared.ts")).unwrap();
        assert_eq!(shared_plug, private_plugins.join("shared.ts"));
        let priv_plug =
            std::fs::read_link(paths.dist.join("opencode/plugins/private-only.ts")).unwrap();
        assert_eq!(priv_plug, private_plugins.join("private-only.ts"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn merge_dirs_empty_when_no_sources() {
        let dir = std::env::temp_dir().join("dotfiles-test-merge-dirs-empty");
        let _ = std::fs::remove_dir_all(&dir);
        let paths = test_paths(&dir);
        std::fs::create_dir_all(&paths.dist).unwrap();

        merge_all_dirs_to(&paths).unwrap();

        for name in &["commands", "skills", "agents", "plugins"] {
            let merge_dir = paths.dist.join(format!("opencode/{}", name));
            assert!(merge_dir.is_dir());
            let entries: Vec<_> = std::fs::read_dir(&merge_dir).unwrap().collect();
            assert!(entries.is_empty(), "{} should be empty", name);
        }

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn merge_dirs_skills_links_subdirectories() {
        let dir = std::env::temp_dir().join("dotfiles-test-merge-dirs-skills");
        let _ = std::fs::remove_dir_all(&dir);
        let paths = test_paths(&dir);

        let public_skills = paths.dotfiles.join("config/opencode/skills");
        std::fs::create_dir_all(public_skills.join("my-skill")).unwrap();
        std::fs::write(public_skills.join("my-skill/SKILL.md"), "# skill").unwrap();
        std::fs::create_dir_all(&paths.dist).unwrap();

        merge_all_dirs_to(&paths).unwrap();

        let link = paths.dist.join("opencode/skills/my-skill");
        let target = std::fs::read_link(&link).unwrap();
        // Target should have trailing slash (subdirectory style)
        let expected = format!("{}/", public_skills.join("my-skill").display());
        assert_eq!(target.to_string_lossy(), expected);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn merge_dirs_removes_stale_entries_before_rebuild() {
        let dir = std::env::temp_dir().join("dotfiles-test-merge-dirs-stale-cleanup");
        let _ = std::fs::remove_dir_all(&dir);
        let paths = test_paths(&dir);

        let public_commands = paths.dotfiles.join("config/opencode/commands");
        std::fs::create_dir_all(&public_commands).unwrap();
        std::fs::create_dir_all(&paths.dist).unwrap();
        std::fs::write(public_commands.join("keep.md"), "keep").unwrap();
        std::fs::write(public_commands.join("remove.md"), "remove").unwrap();

        merge_all_dirs_to(&paths).unwrap();
        assert!(paths.dist.join("opencode/commands/remove.md").exists());

        std::fs::remove_file(public_commands.join("remove.md")).unwrap();

        merge_all_dirs_to(&paths).unwrap();

        assert!(paths.dist.join("opencode/commands/keep.md").exists());
        assert!(!paths.dist.join("opencode/commands/remove.md").exists());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn merge_package_json_public_only() {
        let dir = std::env::temp_dir().join("dotfiles-test-pkg-public");
        let _ = std::fs::remove_dir_all(&dir);
        let paths = test_paths(&dir);

        let public_opencode = paths.dotfiles.join("config/opencode");
        std::fs::create_dir_all(&public_opencode).unwrap();
        std::fs::write(
            public_opencode.join("package.json"),
            r#"{"dependencies": {"@opencode-ai/plugin": "1.0.0"}}"#,
        )
        .unwrap();
        std::fs::create_dir_all(&paths.dist).unwrap();

        let result = merge_opencode_package_json_to(&paths).unwrap();
        assert!(result.is_some());
        let content = std::fs::read_to_string(result.unwrap()).unwrap();
        let json: serde_json::Value = serde_json::from_str(&content).unwrap();
        assert_eq!(json["dependencies"]["@opencode-ai/plugin"], "1.0.0");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn merge_package_json_private_overlay_wins() {
        let dir = std::env::temp_dir().join("dotfiles-test-pkg-overlay");
        let _ = std::fs::remove_dir_all(&dir);
        let paths = test_paths(&dir);

        let public_opencode = paths.dotfiles.join("config/opencode");
        std::fs::create_dir_all(&public_opencode).unwrap();
        std::fs::write(
            public_opencode.join("package.json"),
            r#"{"dependencies": {"@opencode-ai/plugin": "1.0.0", "zod": "3.0.0"}}"#,
        )
        .unwrap();

        std::fs::create_dir_all(paths.opencode_package_json.parent().unwrap()).unwrap();
        std::fs::write(
            &paths.opencode_package_json,
            r#"{"dependencies": {"@opencode-ai/plugin": "2.0.0", "private-dep": "1.0.0"}}"#,
        )
        .unwrap();
        std::fs::create_dir_all(&paths.dist).unwrap();

        let result = merge_opencode_package_json_to(&paths).unwrap();
        assert!(result.is_some());
        let content = std::fs::read_to_string(result.unwrap()).unwrap();
        let json: serde_json::Value = serde_json::from_str(&content).unwrap();

        // Private overlay wins on version
        assert_eq!(json["dependencies"]["@opencode-ai/plugin"], "2.0.0");
        // Public dep preserved
        assert_eq!(json["dependencies"]["zod"], "3.0.0");
        // Private-only dep added
        assert_eq!(json["dependencies"]["private-dep"], "1.0.0");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn merge_package_json_none_when_no_sources() {
        let dir = std::env::temp_dir().join("dotfiles-test-pkg-none");
        let _ = std::fs::remove_dir_all(&dir);
        let paths = test_paths(&dir);
        std::fs::create_dir_all(&paths.dist).unwrap();

        let result = merge_opencode_package_json_to(&paths).unwrap();
        assert!(result.is_none());

        let _ = std::fs::remove_dir_all(&dir);
    }
}
