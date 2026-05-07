# macOS-only Home Manager packages.
#
# `gimp` and `vlc` are not built for aarch64-darwin in current nixpkgs
# (`meta.platforms` excludes Darwin), so they stay as Homebrew casks
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
  ...
}:

let
  fontPackages = [
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerd-fonts.meslo-lg
  ];
  fontPaths = lib.concatStringsSep " " (map (p: "${p}/share/fonts") fontPackages);
in
lib.mkIf pkgs.stdenv.isDarwin {
  home.packages =
    with pkgs;
    [
      aerospace
    ]
    ++ fontPackages;

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
}
