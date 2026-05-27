import { chmodSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { isAbsolute, join } from "node:path";
import { describe, expect, test } from "bun:test";

import { _test } from "../plugins/cargo-build-env";

describe("cargo-build-env pure helpers", () => {
  test("exposes the expected test seam", () => {
    expect(Object.isFrozen(_test)).toBe(true);
    expect(Object.keys(_test).sort()).toEqual([
      "commandPath",
      "isCacheWrapperValue",
      "isKacheWrapperValue",
      "rustCacheEnv",
    ]);
  });

  test("rustCacheEnv prefers kache with sccache fallback", () => {
    expect(_test.rustCacheEnv({
      kache: "/nix/store/bin/kache",
      sccache: "/nix/store/bin/sccache",
    })).toEqual({
      RUSTC_WRAPPER: "/nix/store/bin/kache",
      KACHE_FALLBACK: "/nix/store/bin/sccache",
    });
  });

  test("rustCacheEnv uses kache without fallback when sccache is unavailable", () => {
    expect(_test.rustCacheEnv({ kache: "/opt/bin/kache" })).toEqual({
      RUSTC_WRAPPER: "/opt/bin/kache",
    });
  });

  test("rustCacheEnv preserves sccache-only behavior", () => {
    expect(_test.rustCacheEnv({ sccache: "/opt/bin/sccache" })).toEqual({
      RUSTC_WRAPPER: "/opt/bin/sccache",
    });
  });

  test("rustCacheEnv returns no wrapper when no cache tool is available", () => {
    expect(_test.rustCacheEnv({})).toEqual({});
  });

  test("isCacheWrapperValue flags kache and sccache native compiler wrappers", () => {
    expect(_test.isCacheWrapperValue("/opt/bin/kache clang")).toBe(true);
    expect(_test.isCacheWrapperValue("SCCACHE_CC=/opt/bin/sccache cc")).toBe(true);
    expect(_test.isCacheWrapperValue("/usr/bin/clang")).toBe(false);
    expect(_test.isCacheWrapperValue("gcc")).toBe(false);
  });

  test("isKacheWrapperValue only matches selected kache wrappers", () => {
    expect(_test.isKacheWrapperValue("/nix/store/bin/kache", "/nix/store/bin/kache")).toBe(true);
    expect(_test.isKacheWrapperValue("kache", "/nix/store/bin/kache")).toBe(true);
    expect(_test.isKacheWrapperValue("/usr/local/bin/kache", "/nix/store/bin/kache")).toBe(true);
    expect(_test.isKacheWrapperValue("/usr/local/bin/sccache", "/nix/store/bin/kache")).toBe(false);
    expect(_test.isKacheWrapperValue(undefined, "/nix/store/bin/kache")).toBe(false);
    expect(_test.isKacheWrapperValue(undefined, undefined)).toBe(false);
  });

  test("KACHE_FALLBACK is only part of the desired kache wrapper env", () => {
    expect(_test.rustCacheEnv({ sccache: "/opt/bin/sccache" })).not.toHaveProperty("KACHE_FALLBACK");
  });

  test("commandPath returns absolute paths for relative PATH entries", () => {
    const originalPath = process.env.PATH;
    const originalCwd = process.cwd();
    const temp = mkdtempSync(join(tmpdir(), "cargo-build-env-"));

    try {
      mkdirSync(join(temp, "bin"));
      const kache = join(temp, "bin", "kache");
      writeFileSync(kache, "#!/bin/sh\n");
      chmodSync(kache, 0o755);

      process.chdir(temp);
      process.env.PATH = "bin";

      const resolved = _test.commandPath("kache");
      expect(resolved).toBeDefined();
      expect(isAbsolute(resolved!)).toBe(true);
      expect(realpathSync(resolved!)).toBe(realpathSync(kache));
    } finally {
      process.chdir(originalCwd);
      if (originalPath === undefined) {
        delete process.env.PATH;
      } else {
        process.env.PATH = originalPath;
      }
      rmSync(temp, { force: true, recursive: true });
    }
  });
});
