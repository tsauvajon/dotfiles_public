use std::path::Path;

use anyhow::{Context, Result};

use crate::config::{self, Paths};

/// Create a symlink from `src` to `dest`, creating parent directories as needed.
/// Equivalent to `ln -snf src dest`.
pub fn force_symlink(src: &Path, dest: &Path) -> Result<()> {
    if let Some(parent) = dest.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("creating parent dir for {}", dest.display()))?;
    }

    // Remove existing entry (symlink or file) at dest
    if dest.symlink_metadata().is_ok() {
        if dest.is_dir() && !dest.symlink_metadata()?.is_symlink() {
            // Don't remove real directories
            anyhow::bail!("refusing to remove real directory at {}", dest.display());
        }
        std::fs::remove_file(dest)
            .with_context(|| format!("removing existing {}", dest.display()))?;
    }

    std::os::unix::fs::symlink(src, dest)
        .with_context(|| format!("symlinking {} -> {}", dest.display(), src.display()))?;
    Ok(())
}

/// Remove a managed symlink if it points into our dotfiles or private_build directories.
/// Also removes empty regular files (stale placeholders).
pub fn remove_managed_link_if_present(dest: &Path, paths: &Paths) -> Result<()> {
    let meta = match dest.symlink_metadata() {
        Ok(m) => m,
        Err(_) => return Ok(()), // doesn't exist, nothing to do
    };

    if meta.is_symlink() {
        let target = std::fs::read_link(dest)
            .with_context(|| format!("reading symlink {}", dest.display()))?;
        let target_str = target.to_string_lossy();
        let dotfiles_str = paths.dotfiles.to_string_lossy();
        let build_str = paths.private_build.to_string_lossy();

        if target_str.starts_with(dotfiles_str.as_ref())
            || target_str.starts_with(build_str.as_ref())
        {
            std::fs::remove_file(dest)
                .with_context(|| format!("removing managed symlink {}", dest.display()))?;
        }
        return Ok(());
    }

    // Best-effort cleanup for stale generated placeholders (empty regular files).
    if meta.is_file() && meta.len() == 0 {
        let _ = std::fs::remove_file(dest);
    }

    Ok(())
}

/// Create a managed symlink, respecting skip lists.
/// Skips if destination is in `skip_norms` or source is in `skip_source_norms`.
pub fn managed_link(
    src: &Path,
    dest: &Path,
    skip_norms: &[String],
    skip_source_norms: &[String],
    paths: &Paths,
) -> Result<()> {
    if config::should_skip_dest(dest, &paths.home, skip_norms) {
        crate::log(&format!("Skipping {}", dest.display()));
        remove_managed_link_if_present(dest, paths)?;
        return Ok(());
    }
    if config::should_skip_source(src, &paths.dotfiles, skip_source_norms) {
        crate::log(&format!("Skipping source {}", src.display()));
        remove_managed_link_if_present(dest, paths)?;
        return Ok(());
    }
    force_symlink(src, dest)
}

/// Like `managed_link` but takes a raw string source to preserve trailing slashes.
pub fn managed_link_raw(
    src: &str,
    dest: &Path,
    skip_norms: &[String],
    skip_source_norms: &[String],
    paths: &Paths,
) -> Result<()> {
    if config::should_skip_dest(dest, &paths.home, skip_norms) {
        crate::log(&format!("Skipping {}", dest.display()));
        remove_managed_link_if_present(dest, paths)?;
        return Ok(());
    }
    // Strip trailing slash for source-skip matching
    if config::should_skip_source(
        Path::new(src.trim_end_matches('/')),
        &paths.dotfiles,
        skip_source_norms,
    ) {
        crate::log(&format!("Skipping source {src}"));
        remove_managed_link_if_present(dest, paths)?;
        return Ok(());
    }
    force_symlink(Path::new(src), dest)
}

#[cfg(test)]
mod tests {
    use std::os::unix::fs::symlink;

    use super::*;

    fn temp_paths(dir: &Path) -> Paths {
        Paths {
            dotfiles: dir.join("dotfiles"),
            home: dir.join("home"),
            dev_root: dir.join("dev"),
            dotfiles_config: dir.join("config"),
            private_toml: dir.join("config/private.toml"),
            private_opencode_json: dir.join("config/private-opencode.json"),
            private_skills: dir.join("config/private-skills"),
            private_agents_dir: dir.join("config/private-AGENTS"),
            private_build: dir.join("build"),
        }
    }

    #[test]
    fn force_symlink_creates_link() {
        let dir = std::env::temp_dir().join("dotfiles-test-link");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("src")).unwrap();
        std::fs::write(dir.join("src/file"), "content").unwrap();

        force_symlink(&dir.join("src/file"), &dir.join("dest/file")).unwrap();

        let target = std::fs::read_link(dir.join("dest/file")).unwrap();
        assert_eq!(target, dir.join("src/file"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn force_symlink_replaces_existing() {
        let dir = std::env::temp_dir().join("dotfiles-test-replace");
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("old"), "old").unwrap();
        std::fs::write(dir.join("new"), "new").unwrap();

        symlink(dir.join("old"), dir.join("link")).unwrap();
        force_symlink(&dir.join("new"), &dir.join("link")).unwrap();

        let target = std::fs::read_link(dir.join("link")).unwrap();
        assert_eq!(target, dir.join("new"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn remove_managed_only_removes_ours() {
        let dir = std::env::temp_dir().join("dotfiles-test-managed");
        let _ = std::fs::remove_dir_all(&dir);

        let paths = temp_paths(&dir);
        std::fs::create_dir_all(&paths.dotfiles).unwrap();
        std::fs::create_dir_all(dir.join("dest")).unwrap();
        std::fs::write(paths.dotfiles.join("file"), "x").unwrap();
        std::fs::write(dir.join("external"), "x").unwrap();

        // Our managed symlink - should be removed
        let our_link = dir.join("dest/ours");
        symlink(paths.dotfiles.join("file"), &our_link).unwrap();
        remove_managed_link_if_present(&our_link, &paths).unwrap();
        assert!(!our_link.exists());

        // External symlink - should NOT be removed
        let ext_link = dir.join("dest/ext");
        symlink(dir.join("external"), &ext_link).unwrap();
        remove_managed_link_if_present(&ext_link, &paths).unwrap();
        assert!(ext_link.symlink_metadata().is_ok());

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn remove_managed_cleans_empty_files() {
        let dir = std::env::temp_dir().join("dotfiles-test-empty");
        let _ = std::fs::remove_dir_all(&dir);

        let paths = temp_paths(&dir);
        std::fs::create_dir_all(&dir).unwrap();

        let empty = dir.join("empty");
        std::fs::write(&empty, "").unwrap();
        remove_managed_link_if_present(&empty, &paths).unwrap();
        assert!(!empty.exists());

        let nonempty = dir.join("nonempty");
        std::fs::write(&nonempty, "data").unwrap();
        remove_managed_link_if_present(&nonempty, &paths).unwrap();
        assert!(nonempty.exists());

        let _ = std::fs::remove_dir_all(&dir);
    }
}
