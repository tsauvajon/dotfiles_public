# Integration tests for the cargo build env plugin pure helper harness.
{ pkgs }:

pkgs.runCommand "cargo-build-env-test"
  {
    nativeBuildInputs = [ pkgs.bun ];

    plugin = ../plugins/cargo-build-env.ts;
    testFile = ./cargo-build-env.test.ts;
  }
  ''
    set -eu

    fail() { echo "FAIL: $*" >&2; exit 1; }

    export HOME="$TMPDIR"
    mkdir -p plugins plugin-tests
    cp "$plugin" plugins/cargo-build-env.ts
    cp "$testFile" plugin-tests/cargo-build-env.test.ts

    grep -Fq 'export const _test' plugins/cargo-build-env.ts \
      || fail "cargo-build-env should expose test helpers"
    for helper in \
      commandPath \
      isCacheWrapperValue \
      isKacheWrapperValue \
      rustCacheEnv
    do
      grep -Fq "$helper" plugin-tests/cargo-build-env.test.ts \
        || fail "missing $helper test"
    done

    # The plugin imports @opencode-ai/plugin as a type only; Bun strips it without node_modules.
    bun test plugin-tests/cargo-build-env.test.ts

    echo "all cargo-build-env assertions passed"
    touch "$out"
  ''
