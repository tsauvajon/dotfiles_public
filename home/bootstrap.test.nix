# Regression guard for home/bootstrap.nix.
#
# Currently asserts that the dead `removeDotfilesPath` activation hook
# stays gone. The `~/.config/dotfiles/path` file it cleaned up is no
# longer created by anything in this repo, so the hook only added
# noise to every HM activation.
#
# Add a new case here whenever an activation hook is intentionally
# retired so it is not silently re-introduced by a stray copy/paste.
{ lib }:

let
  source = builtins.readFile ./bootstrap.nix;
in
{
  testRemoveDotfilesPathStaysGone = {
    expr = lib.hasInfix "removeDotfilesPath" source;
    expected = false;
  };

  testCleanupManagedDotfilesPresent = {
    # The legitimate cleanup hook must remain — it makes activation
    # idempotent across machines that previously installed dotfiles
    # by hand. Pair this positive assertion with the negative one
    # above so a regression that drops both is caught.
    expr = lib.hasInfix "cleanupManagedDotfiles" source;
    expected = true;
  };

  testOpencodeTuiJsonCleanupPathPresent = {
    expr = lib.hasInfix ''".config/opencode/tui.json"'' source;
    expected = true;
  };

  testTaskBootstrapPresent = {
    expr = lib.hasInfix "taskBootstrap" source;
    expected = true;
  };
}
