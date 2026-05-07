# Developer CLIs that don't fit the git/shell/fs/rust modules.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    cargo-watch
    docker-credential-helpers
    mdterm
    sqlx-cli
  ];
}
