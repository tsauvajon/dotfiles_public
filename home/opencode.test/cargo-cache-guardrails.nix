# Tests that Cargo cache/toolchain guardrails survive Nix JSON key sorting.
{ lib }:

let
  inherit (import ../lib/opencode-merge.nix { inherit lib; }) mkMergedOpencodeJson;

  merged = mkMergedOpencodeJson { publicRoot = ../../config/opencode; };

  escapeRegex =
    s:
    builtins.replaceStrings
      [
        "\\"
        "."
        "+"
        "?"
        "^"
        "$"
        "("
        ")"
        "["
        "]"
        "{"
        "}"
        "|"
      ]
      [
        "\\\\"
        "\\."
        "\\+"
        "\\?"
        "\\^"
        "\\$"
        "\\("
        "\\)"
        "\\["
        "\\]"
        "\\{"
        "\\}"
        "\\|"
      ]
      s;

  globToRegex =
    pattern:
    if lib.hasSuffix " *" pattern then
      "^"
      + lib.concatStringsSep ".*" (map escapeRegex (lib.splitString "*" (lib.removeSuffix " *" pattern)))
      + "( .*)?$"
    else
      "^" + lib.concatStringsSep ".*" (map escapeRegex (lib.splitString "*" pattern)) + "$";

  lastMatchingAction =
    rules: command:
    let
      matchingKeys = builtins.filter (pattern: builtins.match (globToRegex pattern) command != null) (
        builtins.attrNames rules
      );
    in
    builtins.getAttr (lib.last matchingKeys) rules;

  actionsFor =
    rules: commands:
    map (command: {
      inherit command;
      action = lastMatchingAction rules command;
    }) commands;
  expectedActions = action: commands: map (command: { inherit command action; }) commands;

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
in
{
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

  testRustAgentCargoCacheOverrideDenies = {
    expr = actionsFor (agentRules "rust") agentDeniedCargoCommands;
    expected = expectedActions "deny" agentDeniedCargoCommands;
  };

  testVerifyAgentCargoCacheOverrideDenies = {
    expr = actionsFor (agentRules "verify") agentDeniedCargoCommands;
    expected = expectedActions "deny" agentDeniedCargoCommands;
  };
}
