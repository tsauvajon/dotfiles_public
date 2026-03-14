use anyhow::{Context, Result};

use crate::{
    config::{Paths, PrivateConfig},
    link,
};

/// Generate all private files (gitconfig, goto/config.yml, task/config.toml)
/// and symlink them into place.
pub fn generate_private_files(
    paths: &Paths,
    cfg: &PrivateConfig,
    skip_norms: &[String],
    skip_source_norms: &[String],
) -> Result<()> {
    crate::log(&format!(
        "Loading private config from {}",
        paths.private_toml.display()
    ));

    let missing = cfg.missing_required_keys();
    if !missing.is_empty() {
        crate::warn(&format!(
            "private setup skipped \u{2014} missing keys in {}: {}",
            paths.private_toml.display(),
            missing.join(" ")
        ));
        return Ok(());
    }

    crate::log("Building private files");
    generate_private_files_to(paths, cfg)?;

    crate::log("Symlinking private files");
    link::managed_link(
        &paths.private_build.join("gitconfig"),
        &paths.home.join(".gitconfig"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &paths.private_build.join("goto/config.yml"),
        &paths.home.join(".config/goto/config.yml"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &paths.private_build.join("task/config.toml"),
        &paths.home.join(".config/task/config.toml"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;

    Ok(())
}

/// Generate private files into private_build (without symlinking).
pub fn generate_private_files_to(paths: &Paths, cfg: &PrivateConfig) -> Result<()> {
    let missing = cfg.missing_required_keys();
    if !missing.is_empty() {
        return Ok(());
    }

    let git = cfg.git.as_ref().unwrap();
    let goto = cfg.goto.as_ref().unwrap();
    let vscodium = cfg.vscodium.as_ref().unwrap();

    let git_name = git.name.as_deref().unwrap();
    let git_email = git.email.as_deref().unwrap();
    let git_signing_key = git.signing_key.as_deref().unwrap();
    let goto_api_url = goto.api_url.as_deref().unwrap();
    let trusted_roots = vscodium.trusted_roots.as_deref().unwrap();

    std::fs::create_dir_all(paths.private_build.join("goto"))?;
    std::fs::create_dir_all(paths.private_build.join("task"))?;

    // gitconfig
    let template = std::fs::read_to_string(paths.dotfiles.join("home/gitconfig"))
        .context("reading gitconfig template")?;
    let gitconfig = template
        .replace("YOUR_NAME", git_name)
        .replace("YOUR_EMAIL", git_email)
        .replace("YOUR_GPG_KEY_ID", git_signing_key);
    std::fs::write(paths.private_build.join("gitconfig"), gitconfig)?;

    // goto/config.yml
    let template = std::fs::read_to_string(paths.dotfiles.join("config/goto/config.yml"))
        .context("reading goto config template")?;
    let goto_config = template.replace("YOUR_GOTO_CONFIG_API_URL", goto_api_url);
    std::fs::write(paths.private_build.join("goto/config.yml"), goto_config)?;

    // task/config.toml
    let base = std::fs::read_to_string(paths.dotfiles.join("config/task/config.toml"))
        .context("reading task config template")?;
    let mut task_config = base;
    task_config.push_str("\n[vscodium]\ntrusted_roots = [\n");
    for root in trusted_roots {
        if !root.is_empty() {
            task_config.push_str(&format!("    \"{}\",\n", root));
        }
    }
    task_config.push_str("]\n");
    std::fs::write(paths.private_build.join("task/config.toml"), task_config)?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{GitConfig, GotoConfig, VscodiumConfig};

    fn setup_templates(dir: &std::path::Path) {
        let dotfiles = dir.join("dotfiles");
        std::fs::create_dir_all(dotfiles.join("home")).unwrap();
        std::fs::create_dir_all(dotfiles.join("config/goto")).unwrap();
        std::fs::create_dir_all(dotfiles.join("config/task")).unwrap();

        std::fs::write(
            dotfiles.join("home/gitconfig"),
            "[user]\n\temail = YOUR_EMAIL\n\tname = YOUR_NAME\n\tsigningkey = YOUR_GPG_KEY_ID\n",
        )
        .unwrap();

        std::fs::write(
            dotfiles.join("config/goto/config.yml"),
            "api_url: YOUR_GOTO_CONFIG_API_URL\n",
        )
        .unwrap();

        std::fs::write(
            dotfiles.join("config/task/config.toml"),
            "repos_dir = \"~/dev/repos\"\n",
        )
        .unwrap();
    }

    #[test]
    fn generates_gitconfig() {
        let dir = std::env::temp_dir().join("dotfiles-test-gen-git");
        let _ = std::fs::remove_dir_all(&dir);
        setup_templates(&dir);

        let paths = Paths {
            dotfiles: dir.join("dotfiles"),
            home: dir.join("home"),
            dev_root: dir.join("dev"),
            dotfiles_config: dir.join("config"),
            private_toml: dir.join("config/private.toml"),
            private_opencode_json: dir.join("config/private-opencode.json"),
            private_skills: dir.join("config/private-skills"),
            private_agents_dir: dir.join("config/private-AGENTS"),
            private_build: dir.join("build"),
        };
        std::fs::create_dir_all(&paths.private_build).unwrap();

        let cfg = PrivateConfig {
            git: Some(GitConfig {
                name: Some("Test User".into()),
                email: Some("test@example.com".into()),
                signing_key: Some("ABCD1234".into()),
            }),
            goto: Some(GotoConfig {
                api_url: Some("http://localhost:50002".into()),
            }),
            vscodium: Some(VscodiumConfig {
                trusted_roots: Some(vec!["/home/test/dev".into()]),
            }),
            ..Default::default()
        };

        generate_private_files_to(&paths, &cfg).unwrap();

        let gitconfig = std::fs::read_to_string(paths.private_build.join("gitconfig")).unwrap();
        assert!(gitconfig.contains("email = test@example.com"));
        assert!(gitconfig.contains("name = Test User"));
        assert!(gitconfig.contains("signingkey = ABCD1234"));

        let goto = std::fs::read_to_string(paths.private_build.join("goto/config.yml")).unwrap();
        assert!(goto.contains("api_url: http://localhost:50002"));

        let task = std::fs::read_to_string(paths.private_build.join("task/config.toml")).unwrap();
        assert!(task.contains("[vscodium]"));
        assert!(task.contains("    \"/home/test/dev\","));

        let _ = std::fs::remove_dir_all(&dir);
    }
}
