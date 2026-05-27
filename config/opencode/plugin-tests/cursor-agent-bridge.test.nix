# Integration tests for the cursor-agent bridge plugin pure helper harness.
{ pkgs }:

pkgs.runCommand "cursor-agent-bridge-test"
  {
    nativeBuildInputs = [ pkgs.bun ];

    bridge = ../plugins/cursor-agent-bridge.ts;
    testFile = ./cursor-agent-bridge.test.ts;
  }
  ''
    set -eu

    fail() { echo "FAIL: $*" >&2; exit 1; }

    export HOME="$TMPDIR"
    mkdir -p plugins plugin-tests
    cp "$bridge" plugins/cursor-agent-bridge.ts
    cp "$testFile" plugin-tests/cursor-agent-bridge.test.ts

    grep -Fq 'export const _test' plugins/cursor-agent-bridge.ts \
      || fail "cursor-agent bridge should expose test helpers"
    for helper in \
      contentToText \
      deterministicToolCallId \
      finishChunk \
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
      unsupportedMessage
    do
      grep -Fq "$helper" plugin-tests/cursor-agent-bridge.test.ts \
        || fail "missing $helper test"
    done

    # The bridge imports @opencode-ai/plugin as a type only; Bun strips it without node_modules.
    bun test plugin-tests/cursor-agent-bridge.test.ts

    echo "all cursor-agent-bridge assertions passed"
    touch "$out"
  ''
