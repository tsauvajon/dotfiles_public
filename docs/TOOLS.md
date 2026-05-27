# CLI Tools

Extra command-line tools installed by these dotfiles.

## New Tools

These tools add workflow-specific capabilities rather than replacing one classic command directly.

| Tool              | Installed From                     | Purpose                                            | Quick Reminder                                                |
| ----------------- | ---------------------------------- | -------------------------------------------------- | ------------------------------------------------------------- |
| `atuin`           | `home/shell.nix` via Home Manager  | Shell history search and sync                      | `Ctrl-r` in shell, `atuin search`, `atuin stats`              |
| `backup`          | `home/programs/scripts.nix`        | Copy a file or folder to `<file>.bak`              | `backup config.toml`                                          |
| `cargo-coupling`  | `home/rust.nix`, local package     | Rust coupling/dependency analysis                  | `cargo coupling --help`, `cargo coupling --format json`       |
| `doxx`            | `home/fs.nix`                      | View/export `.docx` files in the terminal          | `doxx file.docx`, `doxx file.docx --export markdown`          |
| `fastfetch`       | `home/fs.nix`                      | System information summary                         | `fastfetch`                                                   |
| `fzf`             | `home/fs.nix`                      | Fuzzy finder                                       | `fzf`, `command \| fzf`                                      |
| `gh`              | `home/programs/git.nix`            | GitHub CLI                                         | `gh pr view`, `gh issue list`                                 |
| `glab`            | `home/programs/git.nix`            | GitLab CLI                                         | `glab mr list`, `glab ci status`                              |
| `glim`            | `home/devtools.nix`, local package | GitLab CI/CD TUI                                   | `glim`                                                        |
| `gurk-rs`         | `home/personal.nix`                | Personal-only Signal Messenger TUI                 | Enable with `dotfiles.personal.enable`; run `gurk`            |
| `jiq`             | `home/fs.nix`                      | Interactive `jq` query builder                     | `jiq data.json`, `curl ... \| jiq`, `Enter` outputs JSON      |
| `mdterm`          | `home/devtools.nix`                | Terminal Markdown viewer                           | `mdterm README.md`                                            |
| `mqttui`          | `home/devtools.nix`                | MQTT broker TUI                                    | `mqttui --broker localhost`, `mqttui --help`                  |
| `opencode-shared` | `home/programs/scripts.nix`        | OpenCode wrapper that reuses a shared local server | `opencode-shared`, `opencode-shared run ...`                  |
| `qpdf`            | `home/fs.nix`                      | PDF structure and page manipulation CLI            | `qpdf in.pdf out.pdf`, `qpdf in.pdf --pages . 1-3 -- out.pdf` |
| `rainfrog`        | `home/devtools.nix`                | PostgreSQL terminal client                         | `rainfrog postgres://user:pass@host/db`, `rainfrog --help`    |
| `rd`              | `home/programs/scripts.nix`        | `rg` plus `delta` with default context             | `rd pattern`, `rd -C5 pattern`                                |
| `sqlx`            | `home/devtools.nix`                | SQLx database/migration CLI                        | `sqlx migrate run`, `sqlx database create`                    |
| `tdf`             | `home/fs.nix`                      | Terminal PDF viewer                                | `tdf file.pdf`, `/` searches, `q` quits                       |
| `tsql`            | `home/devtools.nix`, local package | Keyboard-first PostgreSQL CLI                      | `tsql postgres://user:pass@host/db`, `tsql --help`            |
| `tw`              | `home/fs.nix`                      | TUI for viewing tabular data                       | `tw data.csv`                                                 |
| `zellij`          | `home/shell.nix`                   | Terminal workspace/session manager                 | `zellij`, `zellij attach`                                     |
| `zoxide`          | `home/fs.nix`                      | Smarter `cd` database                              | `z dir`, `zi`                                                 |

Local packages live under `pkgs/` and are exposed as flake packages/checks in `flake.nix`.


## Direct Replacements

These tools replace a classic CLI directly, either through aliases or by acting as the configured pager/viewer.

| Tool      | Replaces              | Installed From                       | Purpose                           | Quick Reminder                                     |
| --------- | --------------------- | ------------------------------------ | --------------------------------- | -------------------------------------------------- |
| `bat`     | `cat`, `less`         | `home/fs.nix`                        | Syntax-highlighted file viewer    | `bat file`, `bat -p file`                          |
| `cyme`    | `lsusb`               | `home/devtools.nix` via Home Manager | Modern cross-platform USB listing | `cyme --lsusb`, `cyme --tree`, `lsusb` alias       |
| `delta`   | Git diff pager        | `home/programs/git.nix`              | Better diff viewer and git pager  | `git diff`, `delta file1 file2`                    |
| `dust`    | `du`                  | `home/fs.nix`                        | Visual disk usage analyzer        | `dust`, `dust -d 2`                                |
| `eza`     | `ls`                  | `home/fs.nix`                        | Modern directory listing          | `eza -la`, `eza --tree`                            |
| `fd`      | `find`                | `home/fs.nix`                        | Fast file finder                  | `fd pattern`, `fd -e nix`                          |
| `gpg-tui` | `gpg` key workflows   | `home/devtools.nix`                  | GPG key management TUI            | `gpg-tui`, `gpg` alias                             |
| `htop`    | `btop`, `top`         | `home/fs.nix`                        | Interactive process viewer        | `htop`, `top` alias                                |
| `ouch`    | `tar`, `zip`, `unzip` | `home/fs.nix`                        | Archive compress/extract CLI      | `ouch d archive.zip`, `ouch c archive.tar.gz dir/` |
| `yazi`    | `lf`, `ranger`        | `home/fs.nix`                        | Terminal file manager             | `yazi`, `y`                                        |
