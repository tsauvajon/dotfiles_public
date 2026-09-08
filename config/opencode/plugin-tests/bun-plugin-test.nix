{ pkgs }:

{
  name,
  helpers,
}:

pkgs.runCommand "${name}-test"
  {
    nativeBuildInputs = [ pkgs.bun ];

    plugin = ../plugins/${name}.ts;
    testFile = ./${name}.test.ts;
  }
  ''
    set -eu

    fail() { echo "FAIL: $*" >&2; exit 1; }

    export HOME="$TMPDIR"
    mkdir -p plugins plugin-tests
    cp "$plugin" "plugins/${name}.ts"
    cp "$testFile" "plugin-tests/${name}.test.ts"

    ! grep -Fq 'export const _test' "plugins/${name}.ts" \
      || fail "${name} must not export non-plugin test helpers"
    grep -Fq 'Object.keys(module)' "plugin-tests/${name}.test.ts" \
      || fail "${name} tests should assert the module only exports default"
    for helper in ${pkgs.lib.concatMapStringsSep " " pkgs.lib.escapeShellArg helpers}; do
      grep -Fq "$helper" "plugin-tests/${name}.test.ts" \
        || fail "missing $helper test"
    done

    # The plugins import @opencode-ai/plugin as a type only; Bun strips it without node_modules.
    bun test "plugin-tests/${name}.test.ts"

    echo "all ${name} assertions passed"
    touch "$out"
  ''
