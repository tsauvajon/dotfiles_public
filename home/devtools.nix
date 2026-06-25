# Developer CLIs that don't fit the git/shell/fs/rust modules.
{ pkgs, ... }:

{
  home.packages = with pkgs; [
    cargo-watch
    cmake
    cyme
    docker-credential-helpers
    eva
    glim
    gpg-tui
    herdr
    mdterm
    mqttui
    rainfrog
    sem
    sqlx-cli
    tsql
    weave
  ];
}
