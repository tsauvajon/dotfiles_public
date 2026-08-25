# Integration tests for the git signing env plugin pure helper harness.
{ pkgs }:

pkgs.runCommand "git-signing-test"
  {
    nativeBuildInputs = [ pkgs.bun ];

    plugin = ../plugins/git-signing.ts;
    testFile = ./git-signing.test.ts;
  }
  ''
    set -eu

    fail() { echo "FAIL: $*" >&2; exit 1; }

    export HOME="$TMPDIR"
    mkdir -p plugins plugin-tests
    cp "$plugin" plugins/git-signing.ts
    cp "$testFile" plugin-tests/git-signing.test.ts

    ! grep -Fq 'export const _test' plugins/git-signing.ts \
      || fail "git-signing must not export non-plugin test helpers"
    grep -Fq 'Object.keys(module)' plugin-tests/git-signing.test.ts \
      || fail "git-signing tests should assert the module only exports default"
    for helper in \
      signingPrivateKeyPath \
      signingConfigEntries \
      existingSigningKey \
      gitSigningEnv
    do
      grep -Fq "$helper" plugin-tests/git-signing.test.ts \
        || fail "missing $helper test"
    done

    # The plugin imports @opencode-ai/plugin as a type only; Bun strips it without node_modules.
    bun test plugin-tests/git-signing.test.ts

    echo "all git-signing assertions passed"
    touch "$out"
  ''
