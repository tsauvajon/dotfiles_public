# Orchestration test for setup.sh using fake external commands.
{ pkgs, lib }:

pkgs.runCommand "setup-test" {
  nativeBuildInputs = [
    pkgs.bash
    pkgs.coreutils
    pkgs.diffutils
    pkgs.gnugrep
  ];
  setup = ../setup.sh;
  importsHelper = ./lib/opencode-imports.sh;
} (builtins.readFile ./setup.test.sh)
