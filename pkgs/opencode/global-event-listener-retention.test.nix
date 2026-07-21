{ pkgs }:

pkgs.runCommand "opencode-global-event-listener-retention-test"
  {
    nativeBuildInputs = [
      pkgs.bun
      pkgs.patch
      pkgs.writableTmpDirAsHomeHook
    ];
  }
  ''
    cp -R ${pkgs.opencode.src} source
    chmod -R u+w source
    patch -d source -p1 < ${./global-event-listener-retention.patch}

    global=source/packages/opencode/src/server/routes/instance/httpapi/handlers/global.ts
    bus=source/packages/opencode/src/bus/global.ts
    test_file=source/packages/opencode/test/server/httpapi-compression.test.ts

    grep -Fq 'request.source instanceof Request ? request.source.signal : undefined' "$global"
    grep -Fq 'Stream.interruptWhen(waitForAbort(signal))' "$global"
    grep -Fq 'GlobalBus.setMaxListeners(100)' "$bus"
    if grep -Eq 'setMaxListeners\((0|Infinity)\)' "$bus"; then
      echo "GlobalBus listener cap must remain finite and nonzero" >&2
      exit 1
    fi

    grep -Fq 'const streamCount = 12' "$test_file"
    grep -Fq 'await waitForGlobalListenerCount(baseline)' "$test_file"
    grep -Fq 'warning.name === "MaxListenersExceededWarning"' "$test_file"

    cp -R ${pkgs.opencode.node_modules}/. source
    cd source/packages/opencode
    bun test test/server/httpapi-compression.test.ts --timeout 30000

    touch "$out"
  ''
