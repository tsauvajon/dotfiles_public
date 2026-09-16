# Hyprbaric status bar for Hyprland, from the pinned upstream AppImage.
# wrapType2 extracts at build time (no runtime FUSE); hardware GL on
# non-NixOS hosts comes from the nixGL wrapper in home/desktop/bar.nix.
{
  lib,
  appimageTools,
  fetchurl,
}:

appimageTools.wrapType2 {
  pname = "hyprbaric";
  version = "0.2.0";

  src = fetchurl {
    # Pinned v0.2.0 AppImage (`%2B` is the `+1` build suffix).
    url = "https://github.com/asaphaaning/hyprbaric/releases/download/v0.2.0/hyprbaric-0.2.0%2B1-linux.AppImage";
    hash = "sha256-SThGCWZynz2h1F3tzGL7Vu89lwXuozd3qZPnGdPSvX8=";
  };

  # The FHS env replaces host /usr and its /etc/profile only prepends to
  # $PATH, so repo-provided tools (grim, slurp, hyprpicker, wl-clipboard,
  # ddcutil, ...) stay reachable via ~/.nix-profile/bin. Host /usr/bin
  # hyprctl and the Hyprland portal are not visible and must come from
  # the env; gtk-layer-shell and libepoxy (needed at load time by the
  # Flutter lib) are core libraries the default env lacks.
  # https://asaphaaning.github.io/hyprbaric/docs/dependencies
  extraPkgs = pkgs: [
    pkgs.gtk-layer-shell
    pkgs.libepoxy
    pkgs.hyprland # hyprctl
    pkgs.xdg-desktop-portal-hyprland
  ];

  meta = {
    description = "Status bar for Hyprland built on Flutter and Rust";
    homepage = "https://github.com/asaphaaning/hyprbaric";
    license = lib.licenses.agpl3Only;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    # Upstream ships only an x86_64 AppImage.
    platforms = [ "x86_64-linux" ];
    mainProgram = "hyprbaric";
  };
}
