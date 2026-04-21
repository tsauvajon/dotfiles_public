# Dotfiles workflow

## Install

```bash
./setup.sh
```

That script links your dotfiles to their expected location, and installs the tools defined in the Nix flake at `home/flakes/toolchain` at , creates `~/dev/repos` and `~/dev/wt`, and runs `task bootstrap`.

### Private OpenCode overrides (MCP, local-only)

OpenCode config is split across `config/opencode/opencode.json` and `config/opencode/commands/`.

Use `~/.config/dotfiles/opencode/opencode.json` for private OpenCode settings you do not want in git.
You can also add private fragments such as `~/.config/dotfiles/opencode/opencode.git.json`.
`setup.sh` deep-merges private fragments and the private overlay over `config/opencode/opencode.json` and generates
`~/.local/share/dotfiles/opencode/opencode.json`, then links that to `~/.config/opencode/opencode.json`.

Place public commands in `config/opencode/commands/` and private commands in
`~/.config/dotfiles/opencode/commands/`. `setup.sh` merges them into
`~/.local/share/dotfiles/opencode/commands/` and links that to `~/.config/opencode/commands`.

Example GitLab MCP config:

```json
{
  "mcp": {
    "GitLab": {
      "type": "remote",
      "url": "https://gitlab.example.com/api/v4/mcp",
      "enabled": true
    }
  }
}
```

After updating your private OpenCode config:

```bash
./setup.sh
opencode mcp auth GitLab
opencode mcp list
```

### OpenCode plugins

Place public plugin files in `config/opencode/plugins/` and private plugins in
`~/.config/dotfiles/opencode/plugins/`. `setup.sh` merges them into
`~/.local/share/dotfiles/opencode/plugins/` and links that to `~/.config/opencode/plugins`.

Plugin dependencies go in `config/opencode/package.json` (public) or
`~/.config/dotfiles/opencode/package.json` (private overlay). After `setup.sh`, install
dependencies with:

```bash
bun install --cwd ~/.config/opencode
```

## Notifications (Hyprland)

- Notification daemon: `mako` (Wayland-native)
- Config path: `config/mako/config`
- Hyprland autostart: `exec-once = mako &` in `config/hypr/hyprland.conf`
- Position: top-right

## Private SSH hosts

`~/.ssh/config` is managed from `config/ssh/config` in the repo.

- Shared defaults belong in `config/ssh/config`
- Private host entries belong in `~/.config/dotfiles/ssh/config`
- The repo-managed file includes the private file first, so per-host entries can keep
  machine-specific `IdentityFile` and related SSH settings

## Node.js policy

Node.js is managed by `asdf`.

- Global default: `home/tool-versions` (currently `nodejs 25.6.1`)
- Project overrides: commit `.tool-versions` per repo
- Package manager: `pnpm` via Corepack
