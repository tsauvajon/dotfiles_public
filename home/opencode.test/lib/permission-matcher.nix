{ lib }:

let
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

  wildcardToRegex =
    pattern:
    builtins.replaceStrings
      [
        "*"
        "?"
      ]
      [
        ".*"
        "."
      ]
      (escapeRegex pattern);

  globToRegex =
    pattern:
    if lib.hasSuffix " *" pattern then
      "^" + wildcardToRegex (lib.removeSuffix " *" pattern) + "( .*)?$"
    else
      "^" + wildcardToRegex pattern + "$";

  matches = pattern: command: builtins.match (globToRegex pattern) command != null;

  lastMatchingAction =
    rules: command:
    let
      matchingKeys = builtins.filter (pattern: matches pattern command) (builtins.attrNames rules);
    in
    if matchingKeys == [ ] then null else rules.${lib.last matchingKeys};
in
{
  inherit matches lastMatchingAction;

  actionsFor =
    rules:
    map (command: {
      inherit command;
      action = lastMatchingAction rules command;
    });

  expectedActions = action: map (command: { inherit command action; });
}
