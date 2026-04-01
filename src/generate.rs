use anyhow::{Context, Result};

use crate::{
    config::{Paths, PrivateConfig},
    link,
};

/// Generate private files (gitconfig, goto/config.yml) from private config values,
/// and symlink them into place. Task config uses the overlay-append pattern instead.
pub fn generate_private_files(
    paths: &Paths,
    cfg: &PrivateConfig,
    skip_norms: &[String],
    skip_source_norms: &[String],
) -> Result<()> {
    crate::log(&format!(
        "Loading private config from {}",
        paths.config_toml.display()
    ));

    let missing = cfg.missing_required_keys();
    if !missing.is_empty() {
        crate::warn(&format!(
            "private setup skipped \u{2014} missing keys in {}: {}",
            paths.config_toml.display(),
            missing.join(" ")
        ));
        return Ok(());
    }

    crate::log("Building private files");
    generate_private_files_to(paths, cfg)?;

    crate::log("Symlinking private files");
    link::managed_link(
        &paths.dist.join("gitconfig"),
        &paths.home.join(".gitconfig"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;
    link::managed_link(
        &paths.dist.join("goto/config.yml"),
        &paths.home.join(".config/goto/config.yml"),
        skip_norms,
        skip_source_norms,
        paths,
    )?;

    Ok(())
}

/// Generate private files into dist (without symlinking).
pub fn generate_private_files_to(paths: &Paths, cfg: &PrivateConfig) -> Result<()> {
    let missing = cfg.missing_required_keys();
    if !missing.is_empty() {
        return Ok(());
    }

    let git = cfg.git.as_ref().unwrap();
    let goto = cfg.goto.as_ref().unwrap();

    let git_name = git.name.as_deref().unwrap();
    let git_email = git.email.as_deref().unwrap();
    let git_signing_key = git.signing_key.as_deref().unwrap();
    let goto_api_url = goto.api_url.as_deref().unwrap();

    std::fs::create_dir_all(paths.dist.join("goto"))?;

    // gitconfig
    let template = std::fs::read_to_string(paths.dotfiles.join("home/gitconfig"))
        .context("reading gitconfig template")?;
    let gitconfig = template
        .replace("YOUR_NAME", git_name)
        .replace("YOUR_EMAIL", git_email)
        .replace("YOUR_GPG_KEY_ID", git_signing_key);
    std::fs::write(paths.dist.join("gitconfig"), gitconfig)?;

    // goto/config.yml
    let template = std::fs::read_to_string(paths.dotfiles.join("config/goto/config.yml"))
        .context("reading goto config template")?;
    let goto_config = template.replace("YOUR_GOTO_CONFIG_API_URL", goto_api_url);
    std::fs::write(paths.dist.join("goto/config.yml"), goto_config)?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{GitConfig, GotoConfig};

    fn setup_templates(dir: &std::path::Path) {
        let dotfiles = dir.join("dotfiles");
        std::fs::create_dir_all(dotfiles.join("home")).unwrap();
        std::fs::create_dir_all(dotfiles.join("config/goto")).unwrap();

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
    }

    #[test]
    fn generates_gitconfig_and_goto() {
        let dir = std::env::temp_dir().join("dotfiles-test-gen-git");
        let _ = std::fs::remove_dir_all(&dir);
        setup_templates(&dir);

        let paths = Paths {
            dotfiles: dir.join("dotfiles"),
            home: dir.join("home"),
            dev_root: dir.join("dev"),
            dotfiles_config: dir.join("config"),
            config_toml: dir.join("config/config.toml"),
            opencode_json: dir.join("config/opencode/opencode.json"),
            opencode_skills: dir.join("config/opencode/skills"),
            opencode_rules: dir.join("config/opencode/rules"),
            opencode_agents: dir.join("config/opencode/agents"),
            opencode_plugins: dir.join("config/opencode/plugins"),
            opencode_package_json: dir.join("config/opencode/package.json"),
            dist: dir.join("dist"),
        };
        std::fs::create_dir_all(&paths.dist).unwrap();

        let cfg = PrivateConfig {
            git: Some(GitConfig {
                name: Some("Test User".into()),
                email: Some("test@example.com".into()),
                signing_key: Some("ABCD1234".into()),
            }),
            goto: Some(GotoConfig {
                api_url: Some("http://localhost:50002".into()),
            }),
            ..Default::default()
        };

        generate_private_files_to(&paths, &cfg).unwrap();

        let gitconfig = std::fs::read_to_string(paths.dist.join("gitconfig")).unwrap();
        assert!(gitconfig.contains("email = test@example.com"));
        assert!(gitconfig.contains("name = Test User"));
        assert!(gitconfig.contains("signingkey = ABCD1234"));

        let goto = std::fs::read_to_string(paths.dist.join("goto/config.yml")).unwrap();
        assert!(goto.contains("api_url: http://localhost:50002"));

        let _ = std::fs::remove_dir_all(&dir);
    }
}
