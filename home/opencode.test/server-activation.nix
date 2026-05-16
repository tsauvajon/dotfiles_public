{ lib }:

let
  opencodeServerModuleSource = builtins.readFile ../opencode-server.nix;
in
{
  testServerRestartDeferredForOpenCodeAgent = {
    expr =
      (lib.hasInfix "running_under_opencode_agent" opencodeServerModuleSource)
      && (lib.hasInfix "AGENT:-" opencodeServerModuleSource)
      && (lib.hasInfix "OPENCODE_RUN_ID:-" opencodeServerModuleSource)
      && (lib.hasInfix "restart deferred because setup is running under an OpenCode agent" opencodeServerModuleSource);
    expected = true;
  };

  testServerHashMarkerWrittenAfterHealthyRestart = {
    expr =
      (lib.hasInfix "if wait_for_health && verify_service; then" opencodeServerModuleSource)
      && (lib.hasInfix ''
          printf '%s\n' "$new_hash" > "$marker"
      '' opencodeServerModuleSource)
      && !(lib.hasInfix ''
      echo "==> OpenCode shared server inputs changed; restarting service"
      printf '%s\n' "$new_hash" > "$marker"
      '' opencodeServerModuleSource);
    expected = true;
  };

  testVerifyServiceChecksManagedState = {
    expr =
      (lib.hasInfix "verify_service()" opencodeServerModuleSource)
      && (lib.hasInfix "active count = [1-9]" opencodeServerModuleSource)
      && (lib.hasInfix "systemctl --user is-active --quiet" opencodeServerModuleSource)
      && (lib.hasInfix "restart failed or did not become healthy" opencodeServerModuleSource);
    expected = true;
  };
}
