{ lib }:

let
  managedEntries = import ../lib/opencode-managed-entries.nix { inherit lib; };
in
{
  testManagedTopLevelEntriesIncludeConditionalAndNestedFiles = {
    expr = managedEntries (
      {
        "opencode/commands" = { };
        "opencode/themes/first.json" = { };
        "opencode/themes/second.json" = { };
      }
      // {
        # Conditional declarations must remain represented even when the
        # current generation does not emit them.
        "opencode/AGENTS.md" = { };
      }
    );
    expected = [
      "AGENTS.md"
      "commands"
      "themes"
    ];
  };
}
