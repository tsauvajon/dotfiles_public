# Tests that Cargo cache/toolchain guardrails survive Nix JSON key sorting.
{ lib }:

let
  inherit (import ../lib/opencode-merge.nix { inherit lib; }) mkMergedOpencodeJson;
  inherit (import ./lib/permission-matcher.nix { inherit lib; })
    actionsFor
    expectedActions
    lastMatchingAction
    matches
    ;

  merged = mkMergedOpencodeJson { publicRoot = ../../config/opencode; };

  globalRules = merged.permission.bash;
  agentRules = name: merged.agent.${name}.permission.bash;

  globalDeniedCargoCommands = [
    "cargo +nightly build"
    "cargo check --config net.git-fetch-with-cli=true"
    "cargo check --target-dir /tmp/opencode-target"
    "cargo run -q --config net.git-fetch-with-cli=true -- --help"
    "cargo run -q --target-dir /tmp/opencode-target -- --help"
    "cargo test --config net.git-fetch-with-cli=true"
    "cargo test --target-dir /tmp/opencode-target"
    "cargo tree --config net.git-fetch-with-cli=true"
    "cargo tree --target-dir /tmp/opencode-target"
    "env CARGO_TARGET_DIR=/tmp/opencode-target cargo check"
    "RUSTC_WRAPPER= cargo check"
    "SCCACHE_DISABLE=1 cargo test"
    "KACHE_CONFIG=/tmp/kache.toml cargo check"
    "KACHE_DISABLED=1 cargo check"
    "bash -c cargo check"
  ];

  cargoRunPassthroughCommands = [
    "cargo"
    "cargo run -- --config binary-arg"
    "cargo run -- --target-dir binary-arg"
    "cargo run -q -- --config binary-arg"
    "cargo run -q -- --target-dir binary-arg"
  ];

  agentDeniedCargoCommands = [
    "cargo +nightly build"
    "cargo build --config net.git-fetch-with-cli=true"
    "cargo check --target-dir /tmp/opencode-target"
    "cargo clippy --config net.git-fetch-with-cli=true"
    "cargo test --target-dir /tmp/opencode-target"
    "cargo tree --config net.git-fetch-with-cli=true"
    "env CARGO_TARGET_DIR=/tmp/opencode-target cargo check"
  ];

  bashRunnerGitCCommands = [
    "git -C /tmp/repo diff --check"
    "git -C /tmp/repo log -5"
    "git -C /tmp/repo rev-parse --show-toplevel"
    "git -C /tmp/repo show HEAD:README.md"
    "git -C /tmp/repo status --short"
  ];
in
{
  testPermissionMatcherBoundaries = {
    expr = {
      bareCommand = matches "cargo *" "cargo";
      commandArguments = matches "cargo *" "cargo check";
      commandPrefix = matches "cargo *" "cargo-nextest";
      questionWildcardOneCharacter = matches "tool? *" "toolx run";
      questionWildcardNeedsCharacter = matches "tool? *" "tool run";
      wildcardWithinToken = matches "scripts/*/check.sh" "scripts/nix/check.sh";
      unmatchedAction = lastMatchingAction { "cargo *" = "allow"; } "git status";
    };
    expected = {
      bareCommand = true;
      commandArguments = true;
      commandPrefix = false;
      questionWildcardOneCharacter = true;
      questionWildcardNeedsCharacter = false;
      wildcardWithinToken = true;
      unmatchedAction = null;
    };
  };

  testGlobalCargoCacheOverrideDenies = {
    expr = actionsFor globalRules globalDeniedCargoCommands;
    expected = expectedActions "deny" globalDeniedCargoCommands;
  };

  testGlobalCargoRunPassthroughStaysAllowed = {
    expr = actionsFor globalRules cargoRunPassthroughCommands;
    expected = expectedActions "allow" cargoRunPassthroughCommands;
  };

  testGeneralAgentCargoCacheOverrideDenies = {
    expr = actionsFor (agentRules "general") agentDeniedCargoCommands;
    expected = expectedActions "deny" agentDeniedCargoCommands;
  };

  testScoutAgentCargoCacheOverrideDenies = {
    expr = actionsFor (agentRules "scout") agentDeniedCargoCommands;
    expected = expectedActions "deny" agentDeniedCargoCommands;
  };

  testImplementAgentCargoCacheOverrideDenies = {
    expr = actionsFor (agentRules "implement") agentDeniedCargoCommands;
    expected = expectedActions "deny" agentDeniedCargoCommands;
  };

  testRustDesignAgentCargoCacheOverrideDenies = {
    expr = actionsFor (agentRules "rust-design") agentDeniedCargoCommands;
    expected = expectedActions "deny" agentDeniedCargoCommands;
  };

  testRustImplementAgentCargoCacheOverrideDenies = {
    expr = actionsFor (agentRules "rust-implement") agentDeniedCargoCommands;
    expected = expectedActions "deny" agentDeniedCargoCommands;
  };

  testBashRunnerAgentCargoCacheOverrideDenies = {
    expr = actionsFor (agentRules "bash-runner") agentDeniedCargoCommands;
    expected = expectedActions "deny" agentDeniedCargoCommands;
  };

  testBashRunnerAgentGitCReadCommandsAllow = {
    expr = actionsFor (agentRules "bash-runner") bashRunnerGitCCommands;
    expected = expectedActions "allow" bashRunnerGitCCommands;
  };

  testBashRunnerAgentGitCWriteCommandsDeny = {
    expr = lastMatchingAction (agentRules "bash-runner") "git -C /tmp/repo commit -m test";
    expected = "deny";
  };
}
