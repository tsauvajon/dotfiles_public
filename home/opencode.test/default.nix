# Aggregator for the OpenCode end-to-end merge tests.
#
# Each child file returns an attrset of `lib.runTests`-compatible
# cases. We union them into a single set, run `lib.runTests`, and
# wrap the outcome in a derivation so it plugs into the flake's
# `checks.${system}.opencode-tests`.
{ pkgs, lib }:

let
  cases =
    (import ./merge-precedence.nix { inherit lib; })
    // (import ./filename-sort.nix { inherit lib; })
    // (import ./rules-modes.nix { inherit lib; })
    // (import ./missing-private.nix { inherit lib; })
    // (import ./public-base-guardrail.nix { inherit lib; });

  failures = lib.runTests cases;
  passedCount = builtins.length (builtins.attrNames cases);
in
pkgs.runCommand "opencode-tests" { } (
  if failures == [ ] then
    ''
      echo "opencode-tests: all ${toString passedCount} cases passed"
      touch "$out"
    ''
  else
    ''
      echo "opencode-tests failures:" >&2
      cat <<'EOF' >&2
      ${builtins.toJSON failures}
      EOF
      exit 1
    ''
)
