# Integration test for home/lib/concat-toml-files.nix.
#
# `concat-toml-files` returns a derivation that stitches TOML text at
# build time, so this wrapper realises the output and asserts on the
# resulting bytes from a derivation.
{ pkgs, lib }:

let
  concatTomlFiles = import ./concat-toml-files.nix { inherit pkgs lib; };

  merged = concatTomlFiles {
    name = "concat-toml-files-test-output.toml";
    base = ./concat-toml-files.test/config.toml;
    fragmentDirs = [
      ./concat-toml-files.test/public
      /nonexistent/concat-toml-files-test
      ./concat-toml-files.test/private
    ];
    prefix = "config";
  };
in
pkgs.runCommand "concat-toml-files-test" { inherit merged; } ''
  set -eu

  expected=${pkgs.writeText "concat-toml-files-expected.toml" ''
base = true

public_10 = true

private_15 = true

collide = "private"
''}

  if ! cmp -s "$merged" "$expected"; then
    echo "FAIL: concat-toml-files output differed" >&2
    echo "--- expected" >&2
    cat "$expected" >&2
    echo "--- actual" >&2
    cat "$merged" >&2
    exit 1
  fi

  touch "$out"
''
