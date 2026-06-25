{
  config,
  lib,
  pkgs,
}:

lib.concatStringsSep ":" (
  [
    "${config.home.homeDirectory}/.local/share/mise/shims"
    "${config.home.profileDirectory}/bin"
    "/nix/var/nix/profiles/default/bin"
    "${config.home.homeDirectory}/go/bin"
    "/usr/local/bin"
    "/opt/homebrew/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ]
  ++ lib.optional pkgs.stdenv.isLinux "/run/current-system/sw/bin"
)
