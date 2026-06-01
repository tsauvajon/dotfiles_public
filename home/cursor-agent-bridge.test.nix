{ lib }:

let
  bridgeModuleSource = builtins.readFile ./cursor-agent-bridge.nix;
  opencodeModuleSource = builtins.readFile ./opencode.nix;
  bridgePluginSource = builtins.readFile ../config/opencode/plugins/cursor-agent-bridge.ts;
in
{
  testCursorAgentBridgeIsDisabledByDefault = {
    expr =
      (lib.hasInfix "default = false;" bridgeModuleSource)
      && (lib.hasInfix "config = lib.mkIf cfg.enable" bridgeModuleSource)
      && (lib.hasInfix "cfg.cursorAgentBridge.enable" opencodeModuleSource)
      && (lib.hasInfix ''builtins.removeAttrs mergedJsonWithCursorProvider.provider [ "cursor-agent" ]'' opencodeModuleSource);
    expected = true;
  };

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
      && (lib.hasInfix ''cd ''${lib.escapeShellArg serviceWorkingDirectory}'' bridgeModuleSource)
      && (lib.hasInfix "WorkingDirectory = serviceWorkingDirectory;" bridgeModuleSource);
    expected = true;
  };

  testCursorAgentBridgeRoutesPermissionsThroughOpenCode = {
    expr =
      (lib.hasInfix "These are OpenCode host tools, not Cursor Agent tools" bridgePluginSource)
      && (lib.hasInfix "Never say shell access is blocked" bridgePluginSource)
      && (lib.hasInfix "Do not invoke Cursor-internal shell, file, edit, or terminal tools" bridgePluginSource)
      && (lib.hasInfix ''"--mode",'' bridgePluginSource)
      && (lib.hasInfix ''"ask",'' bridgePluginSource)
      && (lib.hasInfix ''for (const name of ["HOME", "PATH", "TMPDIR", "USER", "LOGNAME", "CURSOR_API_KEY"])'' bridgePluginSource)
      && !(lib.hasInfix "OPENCODE_CURSOR_AGENT_TRUST" bridgePluginSource)
      && !(lib.hasInfix ''args.push("--trust")'' bridgePluginSource)
      && !(lib.hasInfix ''"SHELL"'' bridgePluginSource);
    expected = true;
  };

  testCursorAgentBridgeSdkBackendIsExplicitAndLazy = {
    expr =
      (lib.hasInfix "OPENCODE_CURSOR_AGENT_BACKEND" bridgePluginSource)
      && (lib.hasInfix "OPENCODE_CURSOR_AGENT_SDK_MODULE" bridgePluginSource)
      && (lib.hasInfix "OPENCODE_CURSOR_AGENT_SDK_MODEL" bridgePluginSource)
      && (lib.hasInfix "CURSOR_API_KEY is required when OPENCODE_CURSOR_AGENT_BACKEND=sdk" bridgePluginSource)
      && (lib.hasInfix "await import(sdkImportSpecifier())" bridgePluginSource)
      && !(lib.hasInfix ''from "@cursor/sdk"'' bridgePluginSource)
      && !(lib.hasInfix "from '@cursor/sdk'" bridgePluginSource);
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
