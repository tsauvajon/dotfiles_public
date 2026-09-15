# Determinate Nix

This repo prefers [Determinate Nix](https://determinate.systems/nix) as its
standalone Nix distribution on macOS and non-NixOS Linux. It is a drop-in
replacement for upstream Nix: the multi-user layout is the same
(`/nix/store`, `/nix/var/nix/profiles/default`, `~/.nix-profile`), so every
path, script, and Home Manager wiring in this repo works unchanged.

Benefits:

- flakes and `nix-command` enabled by default
- receipt-based installer with uninstall and repair (`/nix/nix-installer`)
- systemd units for `nix-daemon` plus `determinate-nixd` service health

Upstream Nix still works. `setup.sh` is vendor-neutral, and
`config/nix/nix.conf` keeps declaring flakes and `nix-command` for upstream
compatibility.

## Fresh install

```bash
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix |
  sh -s -- install --determinate --explain
```

Review the printed plan and confirm. To pin a version, use the tag URL
instead, e.g. `https://install.determinate.systems/nix/tag/v3.22.3`. Then
open a new shell and continue with the
[README quick start](../README.md#quick-start).

## Migrating from an existing upstream install

The Determinate installer refuses to run over an existing Nix installation.
It does not adopt or repair upstream installs, `--force` does not bypass
this, and `--prefer-upstream-nix` is unsupported. Migration is therefore:
uninstall upstream, then fresh-install Determinate.

The consequences are plain: `/nix` store contents and old Home Manager and
profile generations are lost. Everything this repo manages is rebuilt from
`flake.lock` plus the private overlay at `~/.config/dotfiles`, which lives
outside `/nix` and survives. The strategy is: commit work, migrate, rerun
`./setup.sh`.

Perform the migration from an environment that does not depend on `/nix`:
a native TTY login or root console. OpenCode, the Home Manager profile, and
every Nix-managed process run from `/nix`; close them first. If the login
shell itself is Nix-managed, run `sudo chsh -s /bin/bash "$USER"` before
removing `/nix`.

### 1. Preflight (while upstream Nix still works)

Replace `/path/to/dotfiles` with this repo's checkout. Both git worktrees
should be clean or fully committed.

```bash
nix profile list
ls /nix/var/nix/profiles/per-user/"$USER"

git -C /path/to/dotfiles status --porcelain
git -C ~/.config/dotfiles status --porcelain

command -v curl sudo systemctl git   # must resolve to native paths, not /nix/store
getent passwd "$USER"                # login shell must be native (e.g. /bin/bash)
```

### 2. Remove the upstream installation

Follow the
[upstream multi-user uninstall procedure](https://nix.dev/manual/nix/latest/installation/uninstall):

```bash
sudo systemctl stop nix-daemon.service nix-daemon.socket
sudo systemctl disable nix-daemon.service nix-daemon.socket
sudo systemctl daemon-reload
sudo rm -f /etc/systemd/system/nix-daemon.service \
  /etc/systemd/system/nix-daemon.socket
sudo rm -rf /etc/systemd/system/nix-daemon.service.wants \
  /etc/systemd/system/nix-daemon.socket.wants

sudo rm -rf /nix /etc/nix

rm -f ~/.nix-profile ~/.nix-defexpr ~/.nix-channels
sudo rm -f /root/.nix-profile /root/.nix-defexpr /root/.nix-channels
sudo rm -f /etc/profile.d/nix.sh /etc/profile.d/nix-daemon.sh \
  /etc/profile.d/nix-profile.sh

for n in $(seq 1 32); do sudo userdel "nixbld$n" 2>/dev/null; done
sudo groupdel nixbld 2>/dev/null
```

- Removing `/nix` breaks every Home Manager symlink under `$HOME` (shell rc
  files, `~/.config/opencode`, etc.). Expected; the next `./setup.sh` heals
  them.
- Manually copied or overridden systemd units that referenced old store
  paths are covered by the removals above; keep unrelated manual units
  (they are outside `/nix`).

### 3. Install Determinate Nix

Run the fresh-install command above from the same native environment. Then
start a new shell, or source
`/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh` in the current
one.

### 4. Verify and rebuild

```bash
nix --version   # should report: nix (Determinate Nix, ...)
systemctl is-active nix-daemon.socket determinate-nixd.socket
sudo /nix/nix-installer self-test

cd /path/to/dotfiles
./setup.sh
nix flake check --override-input private "path:$HOME/.config/dotfiles"
task doctor
systemctl --user --failed
```

The last command catches user services still pointing at removed store
paths.

## Uninstalling Determinate Nix

```bash
sudo /nix/nix-installer uninstall
```

## Troubleshooting

- `/nix/nix-installer repair` restores shell integration without touching
  the store.
- Never use `--force` to push the installer over conflicting files; resolve
  the conflict instead.
- `--init none` is only for systems without systemd and is not appropriate
  for this repo's hosts.
