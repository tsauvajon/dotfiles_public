{ lib }:

let
  bridgeModuleSource = builtins.readFile ./cursor-agent-bridge.nix;
  bridgePluginSource = builtins.readFile ../config/opencode/plugins/cursor-agent-bridge.ts;
in
{
  testCursorAgentBridgeUsesFixedProviderPort = {
    expr =
      (lib.hasInfix ''port = "43115";'' bridgeModuleSource)
      && (lib.hasInfix ''host = "127.0.0.1";'' bridgeModuleSource)
      && (lib.hasInfix ''const HOST = "127.0.0.1";'' bridgePluginSource)
      && !(lib.hasInfix "port = lib.mkOption" bridgeModuleSource)
      && (lib.hasInfix "OPENCODE_CURSOR_AGENT_BRIDGE_PORT = port;" bridgeModuleSource);
    expected = true;
  };

  testCursorAgentBridgeStandaloneGate = {
    expr =
      (lib.hasInfix "OPENCODE_CURSOR_AGENT_BRIDGE_STANDALONE" bridgeModuleSource)
      && (lib.hasInfix ''import.meta.main && process.env.OPENCODE_CURSOR_AGENT_BRIDGE_STANDALONE === "1"'' bridgePluginSource)
      && (lib.hasInfix "return {};" bridgePluginSource);
    expected = true;
  };

  testCursorAgentBridgeActivationHasManagedHealth = {
    expr =
      (lib.hasInfix "running_under_opencode_agent" bridgeModuleSource)
      && (lib.hasInfix "restart deferred because setup is running under an OpenCode agent" bridgeModuleSource)
      && (lib.hasInfix "verify_service && health" bridgeModuleSource)
      && (lib.hasInfix ''printf '%s\n' "$new_hash" > "$marker"'' bridgeModuleSource);
    expected = true;
  };

  testCursorAgentBridgeUsesTrustedWorkingDirectory = {
    expr =
      (lib.hasInfix "serviceWorkingDirectory = config.home.homeDirectory;" bridgeModuleSource)
      && (lib.hasInfix "cd ${lib.escapeShellArg serviceWorkingDirectory}" bridgeModuleSource)
      && (lib.hasInfix "WorkingDirectory = serviceWorkingDirectory;" bridgeModuleSource);
    expected = true;
  };

  testCursorAgentBridgeSystemdLogsToConfiguredFiles = {
    expr =
      (lib.hasInfix ''StandardOutput = "append:'' bridgeModuleSource)
      && (lib.hasInfix ''StandardError = "append:'' bridgeModuleSource)
      && (lib.hasInfix "StartLimitBurst = 5;" bridgeModuleSource)
      && (lib.hasInfix "StartLimitIntervalSec = 60;" bridgeModuleSource);
    expected = true;
  };
}
