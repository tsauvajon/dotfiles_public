# Integration tests for the cursor-agent bridge plugin pure helper harness.
{ pkgs }:

pkgs.runCommand "cursor-agent-bridge-test"
  {
    nativeBuildInputs = [ pkgs.bun ];

    bridge = ../plugins/cursor-agent-bridge.ts;
    testFile = ./cursor-agent-bridge.test.ts;
    integrationTestFile = ./cursor-agent-bridge.integration.test.ts;
  }
  ''
    set -eu

    fail() { echo "FAIL: $*" >&2; exit 1; }

    export HOME="$TMPDIR"
    mkdir -p plugins plugin-tests
    cp "$bridge" plugins/cursor-agent-bridge.ts
    cp "$testFile" plugin-tests/cursor-agent-bridge.test.ts
    cp "$integrationTestFile" plugin-tests/cursor-agent-bridge.integration.test.ts

    grep -Fq 'export const _test' plugins/cursor-agent-bridge.ts \
      || fail "cursor-agent bridge should expose test helpers"
    for helper in \
      contentToText \
      createToolAwareStreamState \
      cursorEnvironment \
      deterministicToolCallId \
      finishChunk \
      flushPendingToolAwareText \
      healthResponse \
      hasToolRequest \
      modelsResponse \
      normalizeModel \
      openAiUsage \
      parseCursorOutput \
      parsePositiveInteger \
      promptFromMessages \
      roleChunk \
      sanitizeInboundContent \
      toolAwarePromptFromMessages \
      toolCallChunk \
      toolContextFromRequest \
      toolDefinitions \
      updateToolAwareStreamState \
      unsupportedMessage
    do
      grep -Fq "$helper" plugin-tests/cursor-agent-bridge.test.ts \
        || fail "missing $helper test"
    done

    # The bridge imports @opencode-ai/plugin as a type only; Bun strips it without node_modules.
    bun test plugin-tests/cursor-agent-bridge.test.ts plugin-tests/cursor-agent-bridge.integration.test.ts

    echo "all cursor-agent-bridge assertions passed"
    touch "$out"
  ''
