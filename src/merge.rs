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

pub fn merge_opencode_json(paths: &Paths, skip_norms: &[String]) -> Result<()> {
    let dest_link = paths.home.join(".config/opencode/opencode.json");
    if config::should_skip_dest(&dest_link, &paths.home, skip_norms) {
        crate::log(&format!("Skipping {}", dest_link.display()));
        link::remove_managed_link_if_present(&dest_link, paths)?;
        return Ok(());
    }

    let merged_path = merge_opencode_json_to(paths)?;
    link::force_symlink(&merged_path, &dest_link)
}

/// Generate merged opencode.json into private_build, returning the path.
pub fn merge_opencode_json_to(paths: &Paths) -> Result<std::path::PathBuf> {
    let public_config = paths.dotfiles.join("config/opencode/opencode.json");
    let merged_path = paths.private_build.join("opencode/opencode.json");
    std::fs::create_dir_all(merged_path.parent().unwrap())?;

    let public_content = std::fs::read_to_string(&public_config)
        .with_context(|| format!("reading {}", public_config.display()))?;
    let public_json: serde_json::Value = serde_json::from_str(&public_content)
        .with_context(|| format!("parsing {}", public_config.display()))?;

    let merged = if paths.private_opencode_json.exists() {
        let private_content = std::fs::read_to_string(&paths.private_opencode_json)
            .with_context(|| format!("reading {}", paths.private_opencode_json.display()))?;
        let private_json: serde_json::Value = serde_json::from_str(&private_content)
            .with_context(|| format!("parsing {}", paths.private_opencode_json.display()))?;
        deep_merge_json(public_json, private_json)
    } else {
        public_json
    };

    let mut output =
        serde_json::to_string_pretty(&merged).context("serializing merged opencode.json")?;
    output.push('\n');
    std::fs::write(&merged_path, &output)?;

    Ok(merged_path)
}

// ── AGENTS.md merge ─────────────────────────────────────────────────────

pub fn merge_agents(paths: &Paths, skip_norms: &[String], mode: RulesMode) -> Result<()> {
    let dest_link = paths.home.join(".config/opencode/AGENTS.md");

    if config::should_skip_dest(&dest_link, &paths.home, skip_norms) || mode == RulesMode::Disabled
    {
        if mode != RulesMode::Disabled {
            crate::log(&format!("Skipping {}", dest_link.display()));
        }
        link::remove_managed_link_if_present(&dest_link, paths)?;
        return Ok(());
    }

    let merged_path = merge_agents_to(paths, mode)?;
    link::force_symlink(&merged_path, &dest_link)
}

/// Generate merged AGENTS.md into private_build, returning the path.
pub fn merge_agents_to(paths: &Paths, mode: RulesMode) -> Result<std::path::PathBuf> {
    let merged_path = paths.private_build.join("opencode/AGENTS.md");
    std::fs::create_dir_all(merged_path.parent().unwrap())?;

    let mut content = if mode == RulesMode::Merged {
        std::fs::read_to_string(paths.dotfiles.join("config/opencode/AGENTS.md"))
            .context("reading public AGENTS.md")?
    } else {
        String::new()
    };

    let mut appended_any = false;

    if paths.private_rules_dir.is_dir() {
        let mut overlay_files: Vec<_> = std::fs::read_dir(&paths.private_rules_dir)
            .with_context(|| format!("reading {}", paths.private_rules_dir.display()))?
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
            paths.private_rules_dir.display()
        ));
    }

    // Replace __DOTFILES_PATH__ placeholder
    content = content.replace("__DOTFILES_PATH__", &paths.dotfiles.to_string_lossy());

    std::fs::write(&merged_path, &content)?;
    Ok(merged_path)
}

// ── Skills directory merge ──────────────────────────────────────────────

pub fn merge_skills(paths: &Paths, skip_norms: &[String]) -> Result<()> {
    let dest_link = paths.home.join(".config/opencode/skills");
    if config::should_skip_dest(&dest_link, &paths.home, skip_norms) {
        crate::log(&format!("Skipping {}", dest_link.display()));
        link::remove_managed_link_if_present(&dest_link, paths)?;
        return Ok(());
    }

    let merge_dir = merge_skills_to(paths)?;
    link::force_symlink(&merge_dir, &dest_link)
}

/// Generate merged skills directory, returning the path.
pub fn merge_skills_to(paths: &Paths) -> Result<std::path::PathBuf> {
    let merge_dir = paths.private_build.join("opencode/skills");
    std::fs::create_dir_all(&merge_dir)?;

    // Link public skills
    // Bash glob `*/` produces paths with trailing slash; `ln -snf` preserves it.
    // We replicate this so symlink targets are byte-identical.
    let public_skills = paths.dotfiles.join("config/opencode/skills");
    if public_skills.is_dir() {
        for entry in std::fs::read_dir(&public_skills)? {
            let entry = entry?;
            if entry.path().is_dir() {
                let name = entry.file_name();
                let src = append_slash(&entry.path());
                link::force_symlink(Path::new(&src), &merge_dir.join(&name))?;
            }
        }
    }

    // Link private skills (overwrites public on collision)
    if paths.private_skills.is_dir() {
        for entry in std::fs::read_dir(&paths.private_skills)? {
            let entry = entry?;
            if entry.path().is_dir() {
                let name = entry.file_name();
                let src = append_slash(&entry.path());
                link::force_symlink(Path::new(&src), &merge_dir.join(&name))?;
            }
        }
    }

    Ok(merge_dir)
}

// ── Subagents directory merge ───────────────────────────────────────────

pub fn merge_subagents(paths: &Paths, skip_norms: &[String]) -> Result<()> {
    let dest_link = paths.home.join(".config/opencode/agents");
    if config::should_skip_dest(&dest_link, &paths.home, skip_norms) {
        crate::log(&format!("Skipping {}", dest_link.display()));
        link::remove_managed_link_if_present(&dest_link, paths)?;
        return Ok(());
    }

    let merge_dir = merge_subagents_to(paths)?;
    link::force_symlink(&merge_dir, &dest_link)
}

/// Generate merged agents directory, returning the path.
pub fn merge_subagents_to(paths: &Paths) -> Result<std::path::PathBuf> {
    let merge_dir = paths.private_build.join("opencode/agents");
    std::fs::create_dir_all(&merge_dir)?;

    // Symlink public agents (flat .md files)
    let public_agents = paths.dotfiles.join("config/opencode/agents");
    if public_agents.is_dir() {
        for entry in std::fs::read_dir(&public_agents)? {
            let entry = entry?;
            if entry.path().is_file() {
                let name = entry.file_name();
                link::force_symlink(&entry.path(), &merge_dir.join(&name))?;
            }
        }
    }

    // Symlink private agents (overwrites public on collision)
    if paths.private_subagents.is_dir() {
        for entry in std::fs::read_dir(&paths.private_subagents)? {
            let entry = entry?;
            if entry.path().is_file() {
                let name = entry.file_name();
                link::force_symlink(&entry.path(), &merge_dir.join(&name))?;
            }
        }
    }

    Ok(merge_dir)
}

/// Append a trailing `/` to a path, matching bash glob `*/` behavior.
fn append_slash(p: &Path) -> std::ffi::OsString {
    let mut s = p.as_os_str().to_os_string();
    s.push("/");
    s
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

    let base = paths.dotfiles.join("home/aerospace.toml");
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
    let base = paths.dotfiles.join("home/aerospace.toml");
    let merged_path = paths.private_build.join("aerospace.toml");
    let mut overlays = collect_overlays_from(&paths.dotfiles.join("home"), "aerospace.", ".toml")?;
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

    let base = paths.dotfiles.join("home/cargo-config.toml");
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
    let base = paths.dotfiles.join("home/cargo-config.toml");
    let merged_path = paths.private_build.join("cargo-config.toml");
    // Repo-level overlays first (e.g. home/cargo.darwin.toml), then private overlays
    let mut overlays = collect_overlays_from(&paths.dotfiles.join("home"), "cargo.", ".toml")?;
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
    let merged_path = paths.private_build.join("alacritty.toml");
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
    fn merge_overlay_includes_all_when_no_skip() {
        let dir = std::env::temp_dir().join("dotfiles-test-merge-overlay-noskip");
        let _ = std::fs::remove_dir_all(&dir);
        let dotfiles = dir.join("dotfiles");
        std::fs::create_dir_all(dotfiles.join("home")).unwrap();

        std::fs::write(dotfiles.join("home/base.toml"), "[base]\nkey = 1\n").unwrap();
        std::fs::write(
            dotfiles.join("home/cargo.darwin.toml"),
            "[env]\nCC = \"clang\"\n",
        )
        .unwrap();

        let merged = dir.join("merged.toml");
        let overlays = vec![dotfiles.join("home/cargo.darwin.toml")];
        merge_overlay(
            &dotfiles.join("home/base.toml"),
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
        std::fs::create_dir_all(dotfiles.join("home")).unwrap();

        std::fs::write(dotfiles.join("home/base.toml"), "[base]\nkey = 1\n").unwrap();
        std::fs::write(
            dotfiles.join("home/cargo.darwin.toml"),
            "[env]\nCC = \"clang\"\n",
        )
        .unwrap();

        let merged = dir.join("merged.toml");
        let overlays = vec![dotfiles.join("home/cargo.darwin.toml")];
        let skip = vec!["home/cargo.darwin.toml".to_string()];
        merge_overlay(
            &dotfiles.join("home/base.toml"),
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
        std::fs::create_dir_all(dotfiles.join("home")).unwrap();

        std::fs::write(dotfiles.join("home/base.toml"), "[base]\n").unwrap();
        std::fs::write(dotfiles.join("home/cargo.darwin.toml"), "[darwin]\n").unwrap();
        std::fs::write(dotfiles.join("home/cargo.linux.toml"), "[linux]\n").unwrap();

        let merged = dir.join("merged.toml");
        let overlays = vec![
            dotfiles.join("home/cargo.darwin.toml"),
            dotfiles.join("home/cargo.linux.toml"),
        ];
        let skip = vec!["home/cargo.darwin.toml".to_string()];
        merge_overlay(
            &dotfiles.join("home/base.toml"),
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
