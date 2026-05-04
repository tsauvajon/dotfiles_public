use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
};

use anyhow::{Context, Result};

use crate::{config::Paths, link};

/// Link every `*.plist` found under the public and private plist roots into
/// `~/Library/LaunchAgents/`, and remove any previously-managed symlinks in
/// the destination whose source has been deleted or renamed.
///
/// Sources, in scan order:
///   1. Public: `<dotfiles>/config/plist/*.plist`
///   2. Private: `<dotfiles_config>/plist/*.plist`
///
/// Private files win on name collision because later inserts overwrite earlier
/// ones in the desired-sources map, and `link::managed_link` uses
/// `force_symlink` to replace any existing entry at the destination.
pub fn link_all(paths: &Paths, skip_norms: &[String], skip_source_norms: &[String]) -> Result<()> {
    let desired = collect_desired_sources(paths)?;
    remove_stale_links(paths, &desired)?;
    for (name, src) in &desired {
        let dest = paths.home.join("Library/LaunchAgents").join(name);
        link::managed_link(src, &dest, skip_norms, skip_source_norms, paths)?;
    }
    Ok(())
}

/// Collect the set of plist basenames we want to link, mapped to their source
/// paths. Private sources override public sources on name collision.
fn collect_desired_sources(paths: &Paths) -> Result<BTreeMap<String, PathBuf>> {
    let roots = [
        paths.dotfiles.join("config/plist"),
        paths.dotfiles_config.join("plist"),
    ];
    let mut desired: BTreeMap<String, PathBuf> = BTreeMap::new();
    for root in &roots {
        if !root.is_dir() {
            continue;
        }
        let entries =
            std::fs::read_dir(root).with_context(|| format!("reading {}", root.display()))?;
        for entry in entries {
            let entry = entry.with_context(|| format!("iterating {}", root.display()))?;
            let src = entry.path();
            if !src.is_file() {
                continue;
            }
            if src.extension().and_then(|s| s.to_str()) != Some("plist") {
                continue;
            }
            let Some(name) = src.file_name().and_then(|n| n.to_str()) else {
                continue;
            };
            desired.insert(name.to_string(), src);
        }
    }
    Ok(desired)
}

/// Remove `~/Library/LaunchAgents/*` entries that were managed by us (i.e.
/// symlinks pointing into the public dotfiles root, the private dotfiles
/// config root, or the dist build directory) but whose basename is no longer
/// in the desired set. Non-managed entries are left untouched.
fn remove_stale_links(paths: &Paths, desired: &BTreeMap<String, PathBuf>) -> Result<()> {
    let dest_dir = paths.home.join("Library/LaunchAgents");
    if !dest_dir.is_dir() {
        return Ok(());
    }
    let entries =
        std::fs::read_dir(&dest_dir).with_context(|| format!("reading {}", dest_dir.display()))?;
    for entry in entries {
        let entry = entry.with_context(|| format!("iterating {}", dest_dir.display()))?;
        let Some(name) = entry.file_name().to_str().map(str::to_owned) else {
            continue;
        };
        if desired.contains_key(&name) {
            continue;
        }
        remove_if_managed(&entry.path(), paths)?;
    }
    Ok(())
}

/// Remove `dest` if it is a symlink whose target points into any of our
/// managed roots (public dotfiles, private dotfiles config, or the dist build
/// directory). Leaves regular files and foreign symlinks untouched.
fn remove_if_managed(dest: &Path, paths: &Paths) -> Result<()> {
    let Ok(meta) = dest.symlink_metadata() else {
        return Ok(());
    };
    if !meta.is_symlink() {
        return Ok(());
    }
    let target =
        std::fs::read_link(dest).with_context(|| format!("reading symlink {}", dest.display()))?;
    let target_str = target.to_string_lossy().into_owned();

    let managed_roots = [
        paths.dotfiles.to_string_lossy().into_owned(),
        paths.dotfiles_config.to_string_lossy().into_owned(),
        paths.dist.to_string_lossy().into_owned(),
    ];

    if managed_roots
        .iter()
        .any(|root| target_str.starts_with(root))
    {
        std::fs::remove_file(dest)
            .with_context(|| format!("removing managed symlink {}", dest.display()))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::{os::unix::fs::symlink, path::Path};

    use super::*;

    fn temp_paths(dir: &Path) -> Paths {
        Paths {
            dotfiles: dir.join("dotfiles"),
            home: dir.join("home"),
            dev_root: dir.join("dev"),
            dotfiles_config: dir.join("config"),
            config_toml: dir.join("config/config.toml"),
            opencode_json: dir.join("config/opencode/opencode.json"),
            opencode_rules: dir.join("config/opencode/rules"),
            dist: dir.join("build"),
        }
    }

    fn reset(dir: &Path) {
        let _ = std::fs::remove_dir_all(dir);
        std::fs::create_dir_all(dir).unwrap();
    }

    #[test]
    fn links_public_plists() {
        let dir = std::env::temp_dir().join("dotfiles-test-plists-public");
        reset(&dir);
        let paths = temp_paths(&dir);

        let src_dir = paths.dotfiles.join("config/plist");
        std::fs::create_dir_all(&src_dir).unwrap();
        std::fs::write(src_dir.join("foo.plist"), "<plist/>").unwrap();

        link_all(&paths, &[], &[]).unwrap();

        let linked = paths.home.join("Library/LaunchAgents/foo.plist");
        let target = std::fs::read_link(&linked).unwrap();
        assert_eq!(target, src_dir.join("foo.plist"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn links_private_plists() {
        let dir = std::env::temp_dir().join("dotfiles-test-plists-private");
        reset(&dir);
        let paths = temp_paths(&dir);

        let src_dir = paths.dotfiles_config.join("plist");
        std::fs::create_dir_all(&src_dir).unwrap();
        std::fs::write(src_dir.join("bar.plist"), "<plist/>").unwrap();

        link_all(&paths, &[], &[]).unwrap();

        let linked = paths.home.join("Library/LaunchAgents/bar.plist");
        let target = std::fs::read_link(&linked).unwrap();
        assert_eq!(target, src_dir.join("bar.plist"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn private_wins_on_name_collision() {
        let dir = std::env::temp_dir().join("dotfiles-test-plists-collision");
        reset(&dir);
        let paths = temp_paths(&dir);

        let public_dir = paths.dotfiles.join("config/plist");
        let private_dir = paths.dotfiles_config.join("plist");
        std::fs::create_dir_all(&public_dir).unwrap();
        std::fs::create_dir_all(&private_dir).unwrap();
        std::fs::write(public_dir.join("dup.plist"), "public").unwrap();
        std::fs::write(private_dir.join("dup.plist"), "private").unwrap();

        link_all(&paths, &[], &[]).unwrap();

        let linked = paths.home.join("Library/LaunchAgents/dup.plist");
        let target = std::fs::read_link(&linked).unwrap();
        assert_eq!(target, private_dir.join("dup.plist"));

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn ignores_non_plist_files() {
        let dir = std::env::temp_dir().join("dotfiles-test-plists-nonplist");
        reset(&dir);
        let paths = temp_paths(&dir);

        let src_dir = paths.dotfiles_config.join("plist");
        std::fs::create_dir_all(&src_dir).unwrap();
        std::fs::write(src_dir.join("README.md"), "notes").unwrap();

        link_all(&paths, &[], &[]).unwrap();

        let dest_dir = paths.home.join("Library/LaunchAgents");
        assert!(
            !dest_dir.exists() || std::fs::read_dir(&dest_dir).unwrap().next().is_none(),
            "no links should be created for non-plist files"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn skips_when_no_dirs() {
        let dir = std::env::temp_dir().join("dotfiles-test-plists-missing");
        reset(&dir);
        let paths = temp_paths(&dir);

        link_all(&paths, &[], &[]).expect("missing roots should not error");

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn removes_stale_managed_links_when_source_deleted() {
        let dir = std::env::temp_dir().join("dotfiles-test-plists-stale");
        reset(&dir);
        let paths = temp_paths(&dir);

        let private_dir = paths.dotfiles_config.join("plist");
        std::fs::create_dir_all(&private_dir).unwrap();
        std::fs::write(private_dir.join("keep.plist"), "keep").unwrap();
        std::fs::write(private_dir.join("gone.plist"), "gone").unwrap();

        // First run: both links get created.
        link_all(&paths, &[], &[]).unwrap();
        let gone_link = paths.home.join("Library/LaunchAgents/gone.plist");
        let keep_link = paths.home.join("Library/LaunchAgents/keep.plist");
        assert!(gone_link.symlink_metadata().is_ok());
        assert!(keep_link.symlink_metadata().is_ok());

        // Source removed: second run should clean the stale managed link.
        std::fs::remove_file(private_dir.join("gone.plist")).unwrap();
        link_all(&paths, &[], &[]).unwrap();

        assert!(
            gone_link.symlink_metadata().is_err(),
            "stale managed link should be removed"
        );
        assert!(
            keep_link.symlink_metadata().is_ok(),
            "still-wanted link should remain"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn leaves_external_links_alone() {
        let dir = std::env::temp_dir().join("dotfiles-test-plists-external");
        reset(&dir);
        let paths = temp_paths(&dir);

        // A third-party plist the user or another tool installed.
        let external_target = dir.join("third-party.plist");
        std::fs::write(&external_target, "external").unwrap();
        let dest_dir = paths.home.join("Library/LaunchAgents");
        std::fs::create_dir_all(&dest_dir).unwrap();
        let external_link = dest_dir.join("external.plist");
        symlink(&external_target, &external_link).unwrap();

        // Our source set is empty.
        link_all(&paths, &[], &[]).unwrap();

        assert!(
            external_link.symlink_metadata().is_ok(),
            "external symlink must be preserved"
        );

        let _ = std::fs::remove_dir_all(&dir);
    }
}
