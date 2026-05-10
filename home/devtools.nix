# Developer CLIs that don't fit the git/shell/fs/rust modules.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    cargo-watch
    cmake
    cyme
    docker-credential-helpers
    glim
    gpg-tui
    mdterm
    mqttui
    rainfrog
    sqlx-cli
    tsql
  ];
}
