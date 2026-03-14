use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::Deserialize;

#[derive(Debug, Clone)]
pub struct Paths {
    pub dotfiles: PathBuf,
    pub home: PathBuf,
    pub dev_root: PathBuf,
    pub dotfiles_config: PathBuf,
    pub private_toml: PathBuf,
    pub private_opencode_json: PathBuf,
    pub private_skills: PathBuf,
    pub private_agents_dir: PathBuf,
    pub private_build: PathBuf,
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
            private_toml: dotfiles_config.join("private.toml"),
            private_opencode_json: dotfiles_config.join("private-opencode.json"),
            private_skills: dotfiles_config.join("private-skills"),
            private_agents_dir: dotfiles_config.join("private-AGENTS"),
            private_build: home.join(".local/share/dotfiles"),
            dotfiles_config,
            dotfiles,
            home,
            dev_root,
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentsMode {
    Merged,
    PrivateOnly,
    Disabled,
}

#[derive(Debug, Default, Deserialize)]
pub struct PrivateConfig {
    pub git: Option<GitConfig>,
    pub goto: Option<GotoConfig>,
    #[allow(dead_code)]
    pub task: Option<TaskConfig>,
    pub vscodium: Option<VscodiumConfig>,
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

#[derive(Debug, Deserialize)]
pub struct TaskConfig {
    #[allow(dead_code)]
    pub repos_dir: Option<String>,
    #[allow(dead_code)]
    pub wt_dir: Option<String>,
    #[allow(dead_code)]
    pub detached_dir: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct VscodiumConfig {
    pub trusted_roots: Option<Vec<String>>,
}

#[derive(Debug, Default, Deserialize)]
pub struct DotfilesConfig {
    /// Deprecated alias for skip_destinations. Kept for backward compatibility.
    pub skip_links: Option<Vec<String>>,
    /// Destination paths (relative to $HOME) to skip when linking/merging outputs.
    pub skip_destinations: Option<Vec<String>>,
    /// Source paths (relative to dotfiles root) to skip before merge/link.
    pub skip_sources: Option<Vec<String>>,
    pub agents_mode: Option<String>,
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

    pub fn agents_mode(&self) -> AgentsMode {
        match self
            .dotfiles
            .as_ref()
            .and_then(|d| d.agents_mode.as_deref())
        {
            None | Some("") | Some("merged") => AgentsMode::Merged,
            Some("private_only") => AgentsMode::PrivateOnly,
            Some("disabled") => AgentsMode::Disabled,
            Some(other) => {
                crate::warn(&format!(
                    "unknown .dotfiles.agents_mode value '{}', using 'merged'",
                    other
                ));
                AgentsMode::Merged
            }
        }
    }

    pub fn skip_norms(&self, home: &Path) -> Vec<String> {
        let destinations = self
            .dotfiles
            .as_ref()
            .and_then(|d| d.skip_destinations.as_deref())
            .unwrap_or(&[]);
        let legacy = self
            .dotfiles
            .as_ref()
            .and_then(|d| d.skip_links.as_deref())
            .unwrap_or(&[]);

        destinations
            .iter()
            .chain(legacy.iter())
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
        let mut missing: Vec<&str> = required
            .iter()
            .filter(|k| self.get_str(k).is_none())
            .copied()
            .collect();

        // Also check vscodium.trusted_roots exists and is non-empty
        let has_roots = self
            .vscodium
            .as_ref()
            .and_then(|v| v.trusted_roots.as_ref())
            .is_some();
        if !has_roots {
            missing.push(".vscodium.trusted_roots");
        }

        missing
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
        // Both present — warn but don't touch the file
        crate::warn(
            "both skip_links and skip_destinations found in private.toml; \
             remove skip_links manually",
        );
        return Ok(false);
    }

    let migrated = content.replace("skip_links", "skip_destinations");
    std::fs::write(private_toml, &migrated)
        .with_context(|| format!("writing {}", private_toml.display()))?;

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
    fn agents_mode_defaults() {
        let cfg = PrivateConfig::default();
        assert_eq!(cfg.agents_mode(), AgentsMode::Merged);
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

[vscodium]
trusted_roots = ["/home/test/dev"]

[dotfiles]
skip_links = [".config/hypr"]
agents_mode = "merged"
"#;
        let cfg: PrivateConfig = toml::from_str(content).unwrap();
        assert_eq!(cfg.git.as_ref().unwrap().name.as_deref(), Some("Test User"));
        assert_eq!(cfg.agents_mode(), AgentsMode::Merged);
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
}
