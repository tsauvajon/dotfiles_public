import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, test } from "bun:test";

import PrimaryContextPlugin from "../plugins/primary-context";

const _test = PrimaryContextPlugin._test;

function clientWith(parentID: string | undefined) {
  return {
    session: {
      get: async () => ({ data: { parentID } }),
    },
  } as never;
}

describe("primary-context pure helpers", () => {
  test("only default-exports the plugin function", async () => {
    const module = await import("../plugins/primary-context");

    expect(Object.keys(module)).toEqual(["default"]);
  });

  test("exposes the expected test seam", () => {
    expect(typeof PrimaryContextPlugin).toBe("function");
    expect(Object.isFrozen(_test)).toBe(true);
    expect(Object.keys(_test).sort()).toEqual([
      "isRootSession",
      "primaryContextPath",
      "readPrimaryContext",
    ]);
  });

  test("identifies parentless sessions as roots", async () => {
    await expect(_test.isRootSession(clientWith(undefined), "root-session")).resolves.toBe(true);
  });

  test("does not treat child sessions as roots", async () => {
    await expect(_test.isRootSession(clientWith("parent-session"), "child-session")).resolves.toBe(false);
  });

  test("fails closed when session lookup fails", async () => {
    const client = {
      session: {
        get: async () => {
          throw new Error("lookup failed");
        },
      },
    } as never;

    await expect(_test.isRootSession(client, "lookup-failure-session")).resolves.toBe(false);
  });

  test("reads non-empty primary context and ignores empty or missing files", () => {
    const temp = mkdtempSync(join(tmpdir(), "primary-context-"));
    const populated = join(temp, "populated.md");
    const empty = join(temp, "empty.md");

    try {
      writeFileSync(populated, "\nPrimary rules\n");
      writeFileSync(empty, "\n");

      expect(_test.readPrimaryContext(populated)).toBe("Primary rules");
      expect(_test.readPrimaryContext(empty)).toBeUndefined();
      expect(_test.readPrimaryContext(join(temp, "missing.md"))).toBeUndefined();
    } finally {
      rmSync(temp, { force: true, recursive: true });
    }
  });
});
