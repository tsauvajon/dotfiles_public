# Integration tests for the primary-context plugin pure helper harness.
{ pkgs }:

pkgs.runCommand "primary-context-test"
  {
    nativeBuildInputs = [ pkgs.bun ];

    plugin = ../plugins/primary-context.ts;
    testFile = ./primary-context.test.ts;
  }
  ''
    set -eu

    fail() { echo "FAIL: $*" >&2; exit 1; }

    export HOME="$TMPDIR"
    mkdir -p plugins plugin-tests
    cp "$plugin" plugins/primary-context.ts
    cp "$testFile" plugin-tests/primary-context.test.ts

    ! grep -Fq 'export const _test' plugins/primary-context.ts \
      || fail "primary-context must not export non-plugin test helpers"
    grep -Fq 'Object.keys(module)' plugin-tests/primary-context.test.ts \
      || fail "primary-context tests should assert the module only exports default"
    for helper in \
      isRootSession \
      primaryContextPath \
      readPrimaryContext
    do
      grep -Fq "$helper" plugin-tests/primary-context.test.ts \
        || fail "missing $helper test"
    done

    # The plugin imports @opencode-ai/plugin as a type only; Bun strips it without node_modules.
    bun test plugin-tests/primary-context.test.ts

    echo "all primary-context assertions passed"
    touch "$out"
  ''
