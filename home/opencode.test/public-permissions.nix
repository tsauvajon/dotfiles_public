# Tests public OpenCode permission additions after Nix attr-key sorting.
{ lib }:

let
  inherit (import ../lib/opencode-merge.nix { inherit lib; }) mkMergedOpencodeJson;

  merged = mkMergedOpencodeJson { publicRoot = ../../config/opencode; };
  rules = merged.permission.bash;

  escapeRegex =
    s:
    builtins.replaceStrings
      [
        "\\"
        "."
        "+"
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

  wildcardToRegex = s: builtins.replaceStrings [ "*" "?" ] [ ".*" "." ] (escapeRegex s);

  globToRegex =
    pattern:
    if lib.hasSuffix " *" pattern then
      "^" + wildcardToRegex (lib.removeSuffix " *" pattern) + "( .*)?$"
    else
      "^" + wildcardToRegex pattern + "$";

  # OpenCode evaluates matching rules in sorted key order, with the last
  # matching rule deciding the action.
  lastMatchingAction =
    command:
    let
      matchingKeys = builtins.filter (pattern: builtins.match (globToRegex pattern) command != null) (
        builtins.attrNames rules
      );
    in
    builtins.getAttr (lib.last matchingKeys) rules;
in
{
  testPublicPermissionAdditions = {
    expr = map (command: {
      inherit command;
      action = lastMatchingAction command;
    }) [
      "scripts/arch-packages.sh --check"
      "scripts/foo/check.sh"
      "./scripts/check.sh"
      "/nix/store/example/activate"
      "\"/nix/store/example/activate\""
      "sudo \"/nix/store/example/activate\""
      "$BIN --help"
      "\"$BIN\" --help"
      "/usr/bin/curl https://example.test"
      "/usr/bin/unlink example"
      "kevents --help"
      "vault auth help oidc"
      "vault version"
    ];
    expected = [
      {
        command = "scripts/arch-packages.sh --check";
        action = "allow";
      }
      {
        command = "scripts/foo/check.sh";
        action = "allow";
      }
      {
        command = "./scripts/check.sh";
        action = "allow";
      }
      {
        command = "/nix/store/example/activate";
        action = "allow";
      }
      {
        command = "\"/nix/store/example/activate\"";
        action = "allow";
      }
      {
        command = "sudo \"/nix/store/example/activate\"";
        action = "ask";
      }
      {
        command = "$BIN --help";
        action = "deny";
      }
      {
        command = "\"$BIN\" --help";
        action = "deny";
      }
      {
        command = "/usr/bin/curl https://example.test";
        action = "allow";
      }
      {
        command = "/usr/bin/unlink example";
        action = "ask";
      }
      {
        command = "kevents --help";
        action = "ask";
      }
      {
        command = "vault auth help oidc";
        action = "ask";
      }
      {
        command = "vault version";
        action = "ask";
      }
    ];
  };
}
