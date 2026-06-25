{ lib }:

let
  opencodeServerModuleSource = builtins.readFile ../opencode-server.nix;
  managedUserServiceSource = builtins.readFile ../lib/managed-user-service.nix;
  serviceSource = opencodeServerModuleSource + managedUserServiceSource;
in
{
  testServerRestartDeferredForOpenCodeAgent = {
    expr =
      (lib.hasInfix "running_under_opencode_agent" serviceSource)
      && (lib.hasInfix "running_under_opencode_agent && ready" serviceSource)
      && (lib.hasInfix "AGENT:-" serviceSource)
      && (lib.hasInfix "OPENCODE_RUN_ID:-" serviceSource)
      && (lib.hasInfix "restart deferred because setup is running under an OpenCode agent" opencodeServerModuleSource);
    expected = true;
  };

  testServerPendingRestartBreadcrumbLifecycle = {
    expr =
      (lib.hasInfix "opencode-server.pending-restart" opencodeServerModuleSource)
      && (lib.hasInfix "write_pending_restart" serviceSource)
      && (lib.hasInfix "old_hash=%s" serviceSource)
      && (lib.hasInfix "new_hash=%s" serviceSource)
      && (lib.hasInfix "rm -f \"$pending_restart\"" serviceSource);
    expected = true;
  };

  testServerHashMarkerWrittenAfterHealthyRestart = {
    expr =
      (lib.hasInfix "if wait_with_dots; then" serviceSource)
      && (lib.hasInfix ''
        printf '%s\n' "$new_hash" > "$marker"
      '' serviceSource)
      && (lib.hasInfix "echo \"==> \${changedMessage}\"\n            \${serviceRestartCommand}\n            if wait_with_dots; then\n              printf '%s\\n' \"$new_hash\" > \"$marker\"" managedUserServiceSource)
      && !(lib.hasInfix "echo \"==> \${changedMessage}\"\n            \${serviceRestartCommand}\n            printf '%s\\n' \"$new_hash\" > \"$marker\"" managedUserServiceSource);
    expected = true;
  };

  testVerifyServiceChecksManagedState = {
    expr =
      (lib.hasInfix "verify_service()" serviceSource)
      && (lib.hasInfix "active count = [1-9][0-9]*" serviceSource)
      && (lib.hasInfix "systemctl --user is-active --quiet" serviceSource)
      && (lib.hasInfix "restart failed or did not become healthy" opencodeServerModuleSource);
    expected = true;
  };

  testServerStopIsBounded = {
    expr = lib.hasInfix ''
      TimeoutStopSec = "15s";
    '' opencodeServerModuleSource;
    expected = true;
  };
}
