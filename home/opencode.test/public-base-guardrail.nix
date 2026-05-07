# Tests the `publicBaseExists` guardrail in `mkMergedOpencodeJson`.
#
# A bare `opencode.json` in `publicRoot` would be silently ignored by
# the fragment filter (`name != "opencode.json"`), shadowing the
# fragment-only contract documented in AGENTS.md. The merge function
# must abort with `assertMsg` when this file is present.
#
# `builtins.deepSeq` forces the merged value, which triggers the
# assertion if the guardrail is supposed to fire. `builtins.tryEval`
# catches that thrown error and reports `success = false`.
{ lib }:

let
  inherit (import ../lib/opencode-merge.nix { inherit lib; }) mkMergedOpencodeJson;

  # Should fail: fixtures-with-base/ contains a bare `opencode.json`.
  badResult = builtins.tryEval (
    builtins.deepSeq (mkMergedOpencodeJson { publicRoot = ./fixtures-with-base; }) "ok"
  );

  # Should succeed: fixtures/public/ is fragment-only.
  goodResult = builtins.tryEval (
    builtins.deepSeq (mkMergedOpencodeJson { publicRoot = ./fixtures/public; }) "ok"
  );
in
{
  testGuardrailFiresWhenBareOpencodeJsonExists = {
    expr = badResult.success;
    expected = false;
  };

  testNoGuardrailWhenFragmentOnly = {
    expr = goodResult.success;
    expected = true;
  };
}
