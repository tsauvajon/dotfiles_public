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
  cfg = config.programs.apiForCursor;
  apiForCursorSupported = pkgs.stdenv.hostPlatform.system == "aarch64-darwin";
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

  apiForCursorLauncher = pkgs.stdenv.mkDerivation {
    pname = "api-for-cursor-launcher-app";
    version = pkgs.api-for-cursor.version;
    dontUnpack = true;

    installPhase = ''
      runHook preInstall

      app="$out/API for Cursor.app"
      mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

      cat > "$app/Contents/Info.plist" <<'PLIST'
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleDevelopmentRegion</key>
        <string>en</string>
        <key>CFBundleExecutable</key>
        <string>API for Cursor</string>
        <key>CFBundleIdentifier</key>
        <string>ai.standardagents.cursorapi.launcher</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundleName</key>
        <string>API for Cursor</string>
        <key>CFBundleDisplayName</key>
        <string>API for Cursor</string>
        <key>CFBundleIconFile</key>
        <string>APIForCursor</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>LSMinimumSystemVersion</key>
        <string>14.0</string>
        <key>NSHighResolutionCapable</key>
        <true/>
      </dict>
      </plist>
      PLIST
      printf 'APPL????' > "$app/Contents/PkgInfo"

      cat > launcher.c <<'C'
      #include <stdlib.h>
      #include <unistd.h>

      int main(int argc, char *argv[]) {
        char **args = calloc((size_t)argc + 2, sizeof(char *));
        if (args == NULL) {
          return 1;
        }

        args[0] = "/usr/bin/open";
        args[1] = "${pkgs.api-for-cursor}/Applications/API for Cursor.app";
        for (int i = 1; i < argc; i++) {
          args[i + 1] = argv[i];
        }

        execv(args[0], args);
        return 127;
      }
      C
      cc launcher.c -o "$app/Contents/MacOS/API for Cursor"

      cp "${pkgs.api-for-cursor}/Applications/API for Cursor.app/Contents/Resources/APIForCursor.icns" \
        "$app/Contents/Resources/APIForCursor.icns"

      runHook postInstall
    '';
  };

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
  ]
  ++ lib.optionals (personal.enable && personal.plezy.enable) [
    {
      name = "Plezy.app";
      target = "${pkgs.plezy}/Applications/Plezy.app";
    }
  ];

  darwinAppAliasCommands = lib.concatMapStringsSep "\n" (app: ''
    link_app_alias ${lib.escapeShellArg app.name} ${lib.escapeShellArg app.target}
  '') darwinAppAliases;

  apiForCursorRootLauncherCommand = lib.optionalString (apiForCursorSupported && cfg.enable) ''
    link_root_app_launcher 'API for Cursor.app' ${lib.escapeShellArg "${apiForCursorLauncher}/API for Cursor.app"}
  '';
in
{
  options.programs.apiForCursor.enable = lib.mkEnableOption "API for Cursor";

  config = lib.mkMerge [
    {
      warnings = lib.optionals (cfg.enable && !apiForCursorSupported) [
        "programs.apiForCursor.enable is true, but API for Cursor is supported only on aarch64-darwin; no package or app alias will be installed."
      ];
    }
    (lib.mkIf pkgs.stdenv.isDarwin {
      home.packages =
        with pkgs;
        [ aerospace ]
        ++ fontPackages
        ++ ddcPackages
        ++ lib.optionals (personal.enable && personal.plezy.enable) [ plezy ]
        ++ lib.optionals (apiForCursorSupported && cfg.enable) [ api-for-cursor ];

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
      # handle reliably. Most apps get Finder aliases; apps whose aliases do not
      # index well can install a real launcher bundle directly under ~/Applications.
      home.activation.linkDarwinAppAliases = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        aliasDir="${config.home.homeDirectory}/Applications/Nix Apps"
        marker="$aliasDir/.dotfiles-managed"
        oldAerospaceLauncher="${config.home.homeDirectory}/Applications/AeroSpace.app"
        oldAerospaceMarker="$oldAerospaceLauncher/Contents/.dotfiles-managed-aerospace-launcher"
        apiForCursorRootLauncher="${config.home.homeDirectory}/Applications/API for Cursor.app"
        apiForCursorRootMarker="$apiForCursorRootLauncher/Contents/.dotfiles-managed-api-for-cursor-launcher"
        lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

        if [ -f "$oldAerospaceMarker" ]; then
          $DRY_RUN_CMD rm -rf "$oldAerospaceLauncher"
        fi
        if [ -f "$apiForCursorRootMarker" ]; then
          $DRY_RUN_CMD rm -rf "$apiForCursorRootLauncher"
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

        link_root_app_launcher() {
          name="$1"
          source="$2"
          dest="${config.home.homeDirectory}/Applications/$name"
          dest_marker="$dest/Contents/.dotfiles-managed-api-for-cursor-launcher"

          if [ ! -d "$source" ]; then
            printf 'warning: skipping missing app launcher: %s\n' "$source" >&2
            return 0
          fi

          if [ -e "$dest" ] || [ -L "$dest" ]; then
            printf 'error: refusing to replace unmanaged app launcher: %s\n' "$dest" >&2
            exit 1
          fi

          $DRY_RUN_CMD cp -R "$source" "$dest"
          $DRY_RUN_CMD chmod -R u+w "$dest"
          $DRY_RUN_CMD touch "$dest_marker"
          if [ -x /usr/bin/codesign ]; then
            $DRY_RUN_CMD /usr/bin/codesign --force --deep --sign - "$dest" >/dev/null 2>&1 || true
          fi

          if [ -x "$lsregister" ]; then
            $DRY_RUN_CMD "$lsregister" -f "$dest" >/dev/null 2>&1 || true
          fi
        }

        ${darwinAppAliasCommands}
        ${apiForCursorRootLauncherCommand}
      '';
    })
  ];
}
