# macOS-only Home Manager packages.
#
# `gimp` and `vlc` are not built for aarch64-darwin in current nixpkgs
# (`meta.platforms` excludes Darwin), so they stay as Homebrew-managed casks
# (declared in `config/Brewfile`). `keepassxc` is cross-platform and
# lives in `home/apps.nix`.
#
# Nerd fonts: macOS only auto-discovers fonts under `~/Library/Fonts/`,
# `/Library/Fonts/`, and the system bundles. The Nix packages put their
# fonts under `${pkg}/share/fonts/...`, which the OS does not see by
# default. To stay sudo-less (no nix-darwin), we symlink each font file
# from the Nix store into `~/Library/Fonts/`. A marker file lets the
# activation script clean up old symlinks on each run.
{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:

let
  fontPackages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerd-fonts.meslo-lg
  ];
  fontPaths = lib.concatStringsSep " " (map (p: "${p}/share/fonts") fontPackages);
  personal = config.dotfiles.personal;

  # DDC/CI monitor control backend, exposed on PATH for direct use.
  # Apple Silicon Macs use m1ddc (nixpkgs); Intel Macs use kfix/ddcctl
  # built from a pinned flake input. The `monitor-input` wrapper in
  # home/programs/monitor-input.nix calls these by absolute path; they
  # are listed here so the user can also run them directly for
  # debugging or one-off tweaks.
  ddcPackages =
    if pkgs.stdenv.isAarch64 then
      [ pkgs.m1ddc ]
    else if pkgs.stdenv.isx86_64 then
      [ (pkgs.callPackage ./lib/ddcctl.nix { src = inputs.ddcctl-src; }) ]
    else
      [ ];

  # Finder aliases for Nix-installed app bundles. Homebrew-managed casks already
  # install into /Applications and surface in Spotlight/Launchpad without
  # help, so cask-managed apps are intentionally absent here. Keep personal
  # app aliases conditional below so disabled toggles do not force package
  # evaluation.
  darwinAppAliases = [
    {
      name = "AeroSpace.app";
      target = "${pkgs.aerospace}/Applications/AeroSpace.app";
    }
    {
      name = "Alacritty.app";
      target = "${pkgs.alacritty}/Applications/Alacritty.app";
    }
    {
      name = "Kitty.app";
      target = "${pkgs.kitty}/Applications/kitty.app";
    }
    {
      name = "Obsidian.app";
      target = "${pkgs.obsidian}/Applications/Obsidian.app";
    }
    {
      name = "KeePassXC.app";
      target = "${pkgs.keepassxc}/Applications/KeePassXC.app";
    }
  ]
  # Signal Desktop is Nix-managed on Darwin; the install phase puts
  # the app bundle at `$out/Applications/Signal.app` (see nixpkgs
  # `pkgs/by-name/si/signal-desktop/package.nix`). Alias it the same
  # way as the other Nix-installed bundles so it shows up in
  # ~/Applications/Nix Apps and Spotlight.
  ++ lib.optionals (personal.enable && personal.signal.enable) [
    {
      name = "Signal.app";
      target = "${pkgs.signal-desktop}/Applications/Signal.app";
    }
  ];

  darwinAppAliasCommands = lib.concatMapStringsSep "\n" (app: ''
    link_app_alias ${lib.escapeShellArg app.name} ${lib.escapeShellArg app.target}
  '') darwinAppAliases;
in
lib.mkIf pkgs.stdenv.isDarwin {
  home.activation.installHomebrew = lib.hm.dag.entryBefore [ "linkDarwinFonts" ] ''
    if command -v brew >/dev/null 2>&1; then
      exit 0
    fi

    printf '\n'
    printf 'warning: Homebrew not found. To install manually, run:\n'
    printf '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"\n'
    printf '\n'
  '';

  home.packages =
    with pkgs;
    [
      aerospace
      keepassxc
    ]
    ++ fontPackages
    ++ ddcPackages;

  # Symlink Nix-installed font files into ~/Library/Fonts/ on activation.
  # The marker file `dotfiles-managed` records every symlink we own so
  # that fonts removed from `fontPackages` are cleaned up on the next
  # run without touching anything else in ~/Library/Fonts/.
  home.activation.linkDarwinFonts = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    fontDir="${config.home.homeDirectory}/Library/Fonts"
    marker="$fontDir/dotfiles-managed"
    $DRY_RUN_CMD mkdir -p "$fontDir"

    # Drop previously-managed symlinks so removed fonts go away.
    if [ -f "$marker" ]; then
      while IFS= read -r name; do
        [ -z "$name" ] && continue
        if [ -L "$fontDir/$name" ]; then
          $DRY_RUN_CMD rm -f "$fontDir/$name"
        fi
      done < "$marker"
    fi
    $DRY_RUN_CMD : > "$marker"

    for srcRoot in ${fontPaths}; do
      [ -d "$srcRoot" ] || continue
      while IFS= read -r font; do
        [ -z "$font" ] && continue
        name=$(basename "$font")
        dest="$fontDir/$name"
        if [ -e "$dest" ] || [ -L "$dest" ]; then
          printf 'error: refusing to replace unmanaged font: %s\n' "$dest" >&2
          printf '       remove it manually, then rerun setup.sh.\n' >&2
          exit 1
        fi
        $DRY_RUN_CMD ln -s "$font" "$dest"
        $DRY_RUN_CMD sh -c "printf '%s\n' \"$name\" >> \"$marker\""
      done < <(${pkgs.findutils}/bin/find "$srcRoot" -type f \( -name '*.ttf' -o -name '*.otf' \))
    done
  '';

  # Home Manager exposes app bundles through a symlink farm under
  # ~/Applications/Home Manager Apps, which Spotlight and Dock pinning do not
  # handle reliably. Finder aliases are stable, Spotlight-visible app entries.
  home.activation.linkDarwinAppAliases = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    aliasDir="${config.home.homeDirectory}/Applications/Nix Apps"
    marker="$aliasDir/.dotfiles-managed"
    oldAerospaceLauncher="${config.home.homeDirectory}/Applications/AeroSpace.app"
    oldAerospaceMarker="$oldAerospaceLauncher/Contents/.dotfiles-managed-aerospace-launcher"
    lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

    if [ -f "$oldAerospaceMarker" ]; then
      $DRY_RUN_CMD rm -rf "$oldAerospaceLauncher"
    fi

    if [ -e "$aliasDir" ] && [ ! -d "$aliasDir" ]; then
      printf 'error: refusing to replace non-directory: %s\n' "$aliasDir" >&2
      exit 1
    fi

    $DRY_RUN_CMD mkdir -p "$aliasDir"

    if [ -f "$marker" ]; then
      while IFS= read -r name; do
        [ -z "$name" ] && continue
        dest="$aliasDir/$name"
        if [ -e "$dest" ] || [ -L "$dest" ]; then
          $DRY_RUN_CMD rm -rf "$dest"
        fi
      done < "$marker"
    fi
    $DRY_RUN_CMD : > "$marker"

    link_app_alias() {
      name="$1"
      target="$2"
      dest="$aliasDir/$name"

      if [ ! -e "$target" ]; then
        printf 'warning: skipping missing app bundle: %s\n' "$target" >&2
        return 0
      fi

      if [ -e "$dest" ] || [ -L "$dest" ]; then
        printf 'error: refusing to replace unmanaged app alias: %s\n' "$dest" >&2
        exit 1
      fi

      $DRY_RUN_CMD ${pkgs.mkalias}/bin/mkalias "$target" "$dest"
      $DRY_RUN_CMD sh -c 'printf "%s\n" "$1" >> "$2"' sh "$name" "$marker"

      if [ -x "$lsregister" ]; then
        $DRY_RUN_CMD "$lsregister" -f "$dest" >/dev/null 2>&1 || true
      fi
    }

    ${darwinAppAliasCommands}
  '';
}
