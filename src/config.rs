use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::Deserialize;

#[derive(Debug, Clone)]
pub struct Paths {
    pub dotfiles: PathBuf,
    pub home: PathBuf,
    pub dev_root: PathBuf,
    pub dotfiles_config: PathBuf,
    pub config_toml: PathBuf,
    pub opencode_json: PathBuf,
    pub opencode_rules: PathBuf,
    pub opencode_package_json: PathBuf,
    pub dist: PathBuf,
}

impl Paths {
    pub fn resolve() -> Result<Self> {
        let home = PathBuf::from(std::env::var("HOME").context("$HOME not set")?);

        // DOTFILES env or parent of the binary's directory
        let dotfiles = match std::env::var("DOTFILES") {
            Ok(val) => PathBuf::from(val),
            Err(_) => {
                // The binary lives in setup/target/... or is run via nix.
                // Fall back to reading ~/.config/dotfiles/path, or current dir.
                let config_path = home.join(".config/dotfiles/path");
                if config_path.exists() {
                    let content = std::fs::read_to_string(&config_path)
                        .context("reading dotfiles path file")?;
                    PathBuf::from(content.trim())
                } else {
                    // Last resort: assume CWD is the dotfiles repo
                    std::env::current_dir().context("getting current directory")?
                }
            }
        };

        let dev_root = match std::env::var("DEV_ROOT") {
            Ok(val) => PathBuf::from(val),
            Err(_) => home.join("dev"),
        };

        let dotfiles_config = home.join(".config/dotfiles");

        Ok(Self {
            config_toml: dotfiles_config.join("config.toml"),
            opencode_json: dotfiles_config.join("opencode/opencode.json"),
            opencode_rules: dotfiles_config.join("opencode/rules"),
            opencode_package_json: dotfiles_config.join("opencode/package.json"),
            dist: home.join(".local/share/dotfiles"),
            dotfiles_config,
            dotfiles,
            home,
            dev_root,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RulesMode {
    Merged,
    PrivateOnly,
    Disabled,
}

#[derive(Debug, Default, Deserialize)]
pub struct PrivateConfig {
    pub git: Option<GitConfig>,
    pub goto: Option<GotoConfig>,
    pub dotfiles: Option<DotfilesConfig>,
}

#[derive(Debug, Deserialize)]
pub struct GitConfig {
    pub name: Option<String>,
    pub email: Option<String>,
    pub signing_key: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct GotoConfig {
    pub api_url: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
pub struct DotfilesConfig {
    /// Destination paths (relative to $HOME) to skip when linking/merging outputs.
    pub skip_destinations: Option<Vec<String>>,
    /// Source paths (relative to dotfiles root) to skip before merge/link.
    pub skip_sources: Option<Vec<String>>,
    /// Controls how AGENTS.md is built.
    pub rules_mode: Option<String>,
}

impl PrivateConfig {
    pub fn load(path: &Path) -> Result<Self> {
        if !path.exists() {
            return Ok(Self::default());
        }

        let content =
            std::fs::read_to_string(path).with_context(|| format!("reading {}", path.display()))?;
        let cfg: Self =
            toml::from_str(&content).with_context(|| format!("parsing {}", path.display()))?;
        Ok(cfg)
    }

    pub fn rules_mode(&self) -> RulesMode {
        let raw = self
            .dotfiles
            .as_ref()
            .and_then(|d| d.rules_mode.as_deref().filter(|s| !s.is_empty()));

        match raw {
            None | Some("merged") => RulesMode::Merged,
            Some("private_only") => RulesMode::PrivateOnly,
            Some("disabled") => RulesMode::Disabled,
            Some(other) => {
                crate::warn(&format!(
                    "unknown .dotfiles.rules_mode value '{}', using 'merged'",
                    other
                ));
                RulesMode::Merged
            }
        }
    }

    pub fn skip_norms(&self, home: &Path) -> Vec<String> {
        let destinations = self
            .dotfiles
            .as_ref()
            .and_then(|d| d.skip_destinations.as_deref())
            .unwrap_or(&[]);

        destinations
            .iter()
            .filter(|s| !s.is_empty())
            .map(|s| normalize_skip_path(s, home))
            .collect()
    }

    pub fn skip_source_norms(&self) -> Vec<String> {
        self.dotfiles
            .as_ref()
            .and_then(|d| d.skip_sources.as_deref())
            .unwrap_or(&[])
            .iter()
            .filter(|s| !s.is_empty())
            .map(|s| {
                Path::new(s.as_str())
                    .components()
                    .filter(|c| !matches!(c, std::path::Component::CurDir))
                    .collect::<PathBuf>()
                    .to_string_lossy()
                    .into_owned()
            })
            .collect()
    }

    /// Get a private value by dot-path, returning None if empty or missing.
    fn get_str(&self, key: &str) -> Option<&str> {
        let val = match key {
            ".git.name" => self.git.as_ref()?.name.as_deref(),
            ".git.email" => self.git.as_ref()?.email.as_deref(),
            ".git.signing_key" => self.git.as_ref()?.signing_key.as_deref(),
            ".goto.api_url" => self.goto.as_ref()?.api_url.as_deref(),
            _ => None,
        };
        val.filter(|s| !s.is_empty())
    }

    /// Check that all required private keys are present.
    /// Returns the list of missing keys.
    pub fn missing_required_keys(&self) -> Vec<&'static str> {
        let required = [
            ".git.name",
            ".git.email",
            ".git.signing_key",
            ".goto.api_url",
        ];
        required
            .iter()
            .filter(|k| self.get_str(k).is_none())
            .copied()
            .collect()
    }
}

/// Check if a source path should be skipped.
/// `src` is an absolute path; `dotfiles_root` is the repo root.
/// Matches when any skip_source suffix matches the path relative to dotfiles root.
pub fn should_skip_source(src: &Path, dotfiles_root: &Path, skip_source_norms: &[String]) -> bool {
    let src_str = src.to_string_lossy();
    let root_prefix = format!("{}/", dotfiles_root.to_string_lossy());

    let relative = if let Some(rest) = src_str.strip_prefix(&root_prefix) {
        rest
    } else {
        // Not under dotfiles root — never skip
        return false;
    };

    skip_source_norms
        .iter()
        .any(|skip| !skip.is_empty() && relative.ends_with(skip.as_str()))
}

/// Strip $HOME/, ~/, ./ prefix from a path string.
pub fn normalize_skip_path(path: &str, home: &Path) -> String {
    let home_str = home.to_string_lossy();
    let home_prefix = format!("{}/", home_str);

    let stripped = if let Some(rest) = path.strip_prefix(&home_prefix) {
        rest
    } else if let Some(rest) = path.strip_prefix("~/") {
        rest
    } else if let Some(rest) = path.strip_prefix("./") {
        rest
    } else {
        path
    };

    stripped.to_string()
}

/// Auto-rewrite `skip_links` to `skip_destinations` in private.toml.
/// Returns true if the file was rewritten.
/// Errors if both skip_links and skip_destinations are present.
pub fn migrate_skip_links(private_toml: &Path) -> Result<bool> {
    if !private_toml.exists() {
        return Ok(false);
    }

    let content = std::fs::read_to_string(private_toml)
        .with_context(|| format!("reading {}", private_toml.display()))?;

    if !content.contains("skip_links") {
        return Ok(false);
    }
    if content.contains("skip_destinations") {
        anyhow::bail!(
            "both skip_links and skip_destinations found in {}; remove skip_links manually",
            private_toml.display()
        );
    }

    let migrated = content.replace("skip_links", "skip_destinations");
    std::fs::write(private_toml, &migrated)
        .with_context(|| format!("writing {}", private_toml.display()))?;

    Ok(true)
}

/// Auto-rewrite the legacy `agents_mode` key to `rules_mode` in private.toml.
/// Returns true if the file was rewritten.
/// Errors if both agents_mode and rules_mode are present.
pub fn migrate_rules_mode_key(private_toml: &Path) -> Result<bool> {
    if !private_toml.exists() {
        return Ok(false);
    }

    let content = std::fs::read_to_string(private_toml)
        .with_context(|| format!("reading {}", private_toml.display()))?;

    if !content.contains("agents_mode") {
        return Ok(false);
    }
    if content.contains("rules_mode") {
        anyhow::bail!(
            "both agents_mode and rules_mode found in {}; remove agents_mode manually",
            private_toml.display()
        );
    }

    let migrated = content.replace("agents_mode", "rules_mode");
    std::fs::write(private_toml, &migrated)
        .with_context(|| format!("writing {}", private_toml.display()))?;

    Ok(true)
}

/// Migrate private.toml to config.toml.
/// Returns true if migration was performed.
pub fn migrate_private_to_config(legacy: &Path, new_path: &Path) -> Result<bool> {
    if !legacy.exists() {
        return Ok(false);
    }
    if new_path.exists() {
        anyhow::bail!(
            "both {} and {} exist; remove legacy file manually",
            legacy.display(),
            new_path.display()
        );
    }
    std::fs::rename(legacy, new_path)
        .with_context(|| format!("moving {} -> {}", legacy.display(), new_path.display()))?;
    Ok(true)
}

/// Migrate files from the legacy `private-AGENTS/` directory to `opencode/rules/`.
/// Moves each file that doesn't already exist at the destination, then removes the
/// old directory if it is empty afterwards.
/// Returns true if any migration was performed.
/// Migrate files/directories from a legacy directory to a new directory.
/// Moves each entry that doesn't already exist at the destination, then removes the
/// old directory if empty afterwards.
/// Returns true if any migration was performed.
pub fn migrate_dir(legacy: &Path, new_dir: &Path) -> Result<bool> {
    if !legacy.exists() {
        return Ok(false);
    }

    let entries: Vec<_> = std::fs::read_dir(legacy)
        .with_context(|| format!("reading {}", legacy.display()))?
        .filter_map(|e| e.ok())
        .collect();

    if entries.is_empty() {
        let _ = std::fs::remove_dir(legacy);
        return Ok(false);
    }

    std::fs::create_dir_all(new_dir).with_context(|| format!("creating {}", new_dir.display()))?;

    let mut moved_any = false;
    for entry in &entries {
        let src = entry.path();
        let dest = new_dir.join(entry.file_name());
        if dest.exists() {
            crate::warn(&format!(
                "migration: skipping {} (already exists at {})",
                src.display(),
                dest.display()
            ));
            continue;
        }
        std::fs::rename(&src, &dest)
            .with_context(|| format!("moving {} -> {}", src.display(), dest.display()))?;
        moved_any = true;
    }

    // Remove legacy dir if now empty
    let is_empty = std::fs::read_dir(legacy)
        .map(|mut rd| rd.next().is_none())
        .unwrap_or(true);
    if is_empty {
        let _ = std::fs::remove_dir(legacy);
    }

    Ok(moved_any)
}

/// Migrate a single file from legacy path to new path.
/// Returns true if the file was migrated.
/// Errors if both old and new paths exist.
pub fn migrate_file(legacy: &Path, new_path: &Path) -> Result<bool> {
    if !legacy.exists() {
        return Ok(false);
    }
    if new_path.exists() {
        anyhow::bail!(
            "both {} and {} exist; remove legacy file manually",
            legacy.display(),
            new_path.display()
        );
    }
    if let Some(parent) = new_path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("creating parent dir for {}", new_path.display()))?;
    }
    std::fs::rename(legacy, new_path)
        .with_context(|| format!("moving {} -> {}", legacy.display(), new_path.display()))?;
    Ok(true)
}

/// Check if a destination path should be skipped.
pub fn should_skip_dest(dest: &Path, home: &Path, skip_norms: &[String]) -> bool {
    let dest_norm = normalize_skip_path(&dest.to_string_lossy(), home);
    skip_norms
        .iter()
        .any(|skip| !skip.is_empty() && dest_norm.ends_with(skip.as_str()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_strips_home_prefix() {
        let home = Path::new("/Users/thomas");
        assert_eq!(
            normalize_skip_path("/Users/thomas/.config/hypr", home),
            ".config/hypr"
        );
    }

    #[test]
    fn normalize_strips_tilde_prefix() {
        let home = Path::new("/Users/thomas");
        assert_eq!(normalize_skip_path("~/.config/hypr", home), ".config/hypr");
    }

    #[test]
    fn normalize_strips_dot_prefix() {
        let home = Path::new("/Users/thomas");
        assert_eq!(normalize_skip_path("./.config/hypr", home), ".config/hypr");
    }

    #[test]
    fn normalize_no_prefix() {
        let home = Path::new("/Users/thomas");
        assert_eq!(normalize_skip_path(".config/hypr", home), ".config/hypr");
    }

    #[test]
    fn skip_dest_matches_suffix() {
        let home = Path::new("/Users/thomas");
        let skips = vec![".config/hypr".to_string()];
        assert!(should_skip_dest(
            Path::new("/Users/thomas/.config/hypr"),
            home,
            &skips
        ));
    }

    #[test]
    fn skip_dest_no_match() {
        let home = Path::new("/Users/thomas");
        let skips = vec![".config/hypr".to_string()];
        assert!(!should_skip_dest(
            Path::new("/Users/thomas/.config/fish"),
            home,
            &skips
        ));
    }

    #[test]
    fn skip_dest_empty_skip_ignored() {
        let home = Path::new("/Users/thomas");
        let skips = vec!["".to_string()];
        assert!(!should_skip_dest(
            Path::new("/Users/thomas/.config/fish"),
            home,
            &skips
        ));
    }

    #[test]
    fn rules_mode_defaults() {
        let cfg = PrivateConfig::default();
        assert_eq!(cfg.rules_mode(), RulesMode::Merged);
    }

    #[test]
    fn rules_mode_reads_rules_mode_key() {
        let content = "[dotfiles]\nrules_mode = \"private_only\"\n";
        let cfg: PrivateConfig = toml::from_str(content).unwrap();
        assert_eq!(cfg.rules_mode(), RulesMode::PrivateOnly);
    }

    #[test]
    fn parse_example_toml() {
        let content = r#"
[git]
name = "Test User"
email = "test@example.com"
signing_key = "ABCD1234ABCD1234"

[goto]
api_url = "http://localhost:50002"

[dotfiles]
skip_destinations = [".config/hypr"]
rules_mode = "merged"
"#;
        let cfg: PrivateConfig = toml::from_str(content).unwrap();
        assert_eq!(cfg.git.as_ref().unwrap().name.as_deref(), Some("Test User"));
        assert_eq!(cfg.rules_mode(), RulesMode::Merged);
        assert!(cfg.missing_required_keys().is_empty());
    }

    #[test]
    fn parse_skip_destinations() {
        let content = r#"
[dotfiles]
skip_destinations = [".config/hypr", ".config/mako"]
"#;
        let cfg: PrivateConfig = toml::from_str(content).unwrap();
        let home = Path::new("/home/test");
        let norms = cfg.skip_norms(home);
        assert_eq!(norms, vec![".config/hypr", ".config/mako"]);
    }

    #[test]
    fn parse_skip_sources() {
        let content = r#"
[dotfiles]
skip_sources = ["home/cargo.darwin.toml", "config/hypr"]
"#;
        let cfg: PrivateConfig = toml::from_str(content).unwrap();
        let norms = cfg.skip_source_norms();
        assert_eq!(norms, vec!["home/cargo.darwin.toml", "config/hypr"]);
    }

    #[test]
    fn skip_sources_strips_dot_slash() {
        let content = r#"
[dotfiles]
skip_sources = ["./home/cargo.darwin.toml"]
"#;
        let cfg: PrivateConfig = toml::from_str(content).unwrap();
        let norms = cfg.skip_source_norms();
        assert_eq!(norms, vec!["home/cargo.darwin.toml"]);
    }

    #[test]
    fn should_skip_source_matches() {
        let root = Path::new("/mnt/dotfiles");
        let skips = vec!["home/cargo.darwin.toml".to_string()];

        assert!(should_skip_source(
            Path::new("/mnt/dotfiles/home/cargo.darwin.toml"),
            root,
            &skips
        ));
        assert!(!should_skip_source(
            Path::new("/mnt/dotfiles/home/cargo-config.toml"),
            root,
            &skips
        ));
    }

    #[test]
    fn should_skip_source_outside_root() {
        let root = Path::new("/mnt/dotfiles");
        let skips = vec!["cargo.darwin.toml".to_string()];

        // Path not under dotfiles root — never skipped
        assert!(!should_skip_source(
            Path::new("/other/cargo.darwin.toml"),
            root,
            &skips
        ));
    }

    #[test]
    fn migrate_rewrites_skip_links() {
        let dir = std::env::temp_dir().join("dotfiles-test-migrate-rewrite");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let toml_path = dir.join("private.toml");
        std::fs::write(&toml_path, "[dotfiles]\nskip_links = [\".config/hypr\"]\n").unwrap();

        assert!(migrate_skip_links(&toml_path).unwrap());
        let content = std::fs::read_to_string(&toml_path).unwrap();
        assert!(content.contains("skip_destinations"));
        assert!(!content.contains("skip_links"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn migrate_noop_when_already_migrated() {
        let dir = std::env::temp_dir().join("dotfiles-test-migrate-noop");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let toml_path = dir.join("private.toml");
        std::fs::write(&toml_path, "[dotfiles]\nskip_destinations = []\n").unwrap();

        assert!(!migrate_skip_links(&toml_path).unwrap());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn migrate_noop_when_missing() {
        let path = std::env::temp_dir().join("dotfiles-test-migrate-missing/private.toml");
        let _ = std::fs::remove_file(&path);
        assert!(!migrate_skip_links(&path).unwrap());
    }

    #[test]
    fn migrate_rules_mode_key_rewrites_key() {
        let dir = std::env::temp_dir().join("dotfiles-test-migrate-rules-mode-key");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let toml_path = dir.join("private.toml");
        std::fs::write(&toml_path, "[dotfiles]\nagents_mode = \"merged\"\n").unwrap();

        assert!(migrate_rules_mode_key(&toml_path).unwrap());
        let content = std::fs::read_to_string(&toml_path).unwrap();
        assert!(content.contains("rules_mode"));
        assert!(!content.contains("agents_mode"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn migrate_rules_mode_key_errs_when_both_present() {
        let dir = std::env::temp_dir().join("dotfiles-test-migrate-rules-mode-key-both");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let toml_path = dir.join("private.toml");
        std::fs::write(
            &toml_path,
            "[dotfiles]\nagents_mode = \"merged\"\nrules_mode = \"disabled\"\n",
        )
        .unwrap();

        let result = migrate_rules_mode_key(&toml_path);
        let err = result.unwrap_err();
        assert!(err.to_string().contains("both agents_mode and rules_mode"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn migrate_dir_moves_files() {
        let dir = std::env::temp_dir().join("dotfiles-test-migrate-rules-dir");
        let _ = std::fs::remove_dir_all(&dir);
        let legacy = dir.join("private-AGENTS");
        let new_dir = dir.join("opencode/rules");
        std::fs::create_dir_all(&legacy).unwrap();
        std::fs::write(legacy.join("01-extra.md"), "# extra\n").unwrap();

        assert!(migrate_dir(&legacy, &new_dir).unwrap());
        assert!(new_dir.join("01-extra.md").exists());
        assert!(!legacy.exists(), "legacy dir should be removed when empty");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn migrate_dir_skips_existing_dest() {
        let dir = std::env::temp_dir().join("dotfiles-test-migrate-rules-dir-skip");
        let _ = std::fs::remove_dir_all(&dir);
        let legacy = dir.join("private-AGENTS");
        let new_dir = dir.join("opencode/rules");
        std::fs::create_dir_all(&legacy).unwrap();
        std::fs::create_dir_all(&new_dir).unwrap();
        std::fs::write(legacy.join("01-extra.md"), "old\n").unwrap();
        std::fs::write(new_dir.join("01-extra.md"), "new\n").unwrap();

        // Returns false since the only file was skipped (not moved)
        assert!(!migrate_dir(&legacy, &new_dir).unwrap());
        // Destination content untouched
        assert_eq!(
            std::fs::read_to_string(new_dir.join("01-extra.md")).unwrap(),
            "new\n"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn migrate_dir_noop_when_missing() {
        let dir = std::env::temp_dir().join("dotfiles-test-migrate-rules-dir-missing");
        let legacy = dir.join("private-AGENTS");
        let new_dir = dir.join("opencode/rules");
        assert!(!migrate_dir(&legacy, &new_dir).unwrap());
    }
}
