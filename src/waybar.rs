use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use config::Paths;

use crate::{config, link};

pub fn generate_and_link(
    paths: &Paths,
    skip_norms: &[String],
    skip_source_norms: &[String],
) -> Result<()> {
    let source_dir = paths.dotfiles.join("config/waybar");
    let dest_link = paths.home.join(".config/waybar");

    if config::should_skip_dest(&dest_link, &paths.home, skip_norms) {
        crate::log(&format!("Skipping {}", dest_link.display()));
        link::remove_managed_link_if_present(&dest_link, paths)?;
        return Ok(());
    }

    if config::should_skip_source(&source_dir, &paths.dotfiles, skip_source_norms) {
        crate::log(&format!("Skipping source {}", source_dir.display()));
        link::remove_managed_link_if_present(&dest_link, paths)?;
        return Ok(());
    }

    let generated_dir = generate_to(paths, skip_source_norms)?;
    link::force_symlink(&generated_dir, &dest_link)
}

pub fn generate_to(paths: &Paths, skip_source_norms: &[String]) -> Result<PathBuf> {
    let source_dir = paths.dotfiles.join("config/waybar");
    let generated_dir = paths.dist.join("waybar");

    replace_dir(&generated_dir)?;
    link_entries(&source_dir, &generated_dir, paths, skip_source_norms)?;
    write_style_css(&source_dir, &generated_dir, paths, skip_source_norms)?;

    Ok(generated_dir)
}

fn replace_dir(path: &Path) -> Result<()> {
    match path.symlink_metadata() {
        Ok(meta) if meta.is_symlink() || meta.is_file() => std::fs::remove_file(path)
            .with_context(|| format!("removing existing {}", path.display()))?,
        Ok(_) => std::fs::remove_dir_all(path)
            .with_context(|| format!("removing existing {}", path.display()))?,
        Err(_) => {}
    }

    std::fs::create_dir_all(path).with_context(|| format!("creating {}", path.display()))
}

fn link_entries(
    source_dir: &Path,
    generated_dir: &Path,
    paths: &Paths,
    skip_source_norms: &[String],
) -> Result<()> {
    for entry in std::fs::read_dir(source_dir)
        .with_context(|| format!("reading {}", source_dir.display()))?
    {
        let entry = entry?;
        let source = entry.path();
        if source.file_name().is_some_and(|name| name == "style.css") {
            continue;
        }
        if config::should_skip_source(&source, &paths.dotfiles, skip_source_norms) {
            continue;
        }

        link::force_symlink(&source, &generated_dir.join(entry.file_name()))?;
    }

    Ok(())
}

fn write_style_css(
    source_dir: &Path,
    generated_dir: &Path,
    paths: &Paths,
    skip_source_norms: &[String],
) -> Result<()> {
    let source = source_dir.join("styles/index.scss");
    if config::should_skip_source(&source, &paths.dotfiles, skip_source_norms) {
        return Ok(());
    }

    let css = grass::from_path(
        &source,
        &grass::Options::default().style(grass::OutputStyle::Expanded),
    )
    .map_err(|err| anyhow::anyhow!(err))
    .with_context(|| format!("compiling {}", source.display()))?;

    std::fs::write(generated_dir.join("style.css"), css)
        .with_context(|| format!("writing {}/style.css", generated_dir.display()))
}

#[cfg(test)]
mod tests {
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

    #[test]
    fn generates_style_css_from_scss() {
        let dir = std::env::temp_dir().join("dotfiles-test-waybar");
        let _ = std::fs::remove_dir_all(&dir);

        let paths = temp_paths(&dir);
        let waybar = paths.dotfiles.join("config/waybar");
        std::fs::create_dir_all(waybar.join("styles")).unwrap();
        std::fs::write(waybar.join("config.jsonc"), "{}").unwrap();
        std::fs::write(
            waybar.join("styles/index.scss"),
            "$color: red; #clock { color: $color; }",
        )
        .unwrap();
        std::fs::write(waybar.join("style.css"), "stale").unwrap();

        let generated = generate_to(&paths, &[]).unwrap();

        let css = std::fs::read_to_string(generated.join("style.css")).unwrap();
        assert!(css.contains("#clock"));
        assert!(css.contains("color: red"));
        assert_eq!(
            std::fs::read_link(generated.join("config.jsonc")).unwrap(),
            waybar.join("config.jsonc")
        );
        assert!(!generated
            .join("style.css")
            .symlink_metadata()
            .unwrap()
            .is_symlink());

        let _ = std::fs::remove_dir_all(&dir);
    }
}
