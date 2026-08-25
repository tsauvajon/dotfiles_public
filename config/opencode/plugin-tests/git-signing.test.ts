import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { describe, expect, test } from "bun:test";

import GitSigningPlugin from "../plugins/git-signing";

const _test = GitSigningPlugin._test;

describe("git-signing pure helpers", () => {
  test("only default-exports the plugin function", async () => {
    const module = await import("../plugins/git-signing");

    expect(Object.keys(module)).toEqual(["default"]);
  });

  test("exposes the expected test seam", () => {
    expect(typeof GitSigningPlugin).toBe("function");
    expect(Object.isFrozen(_test)).toBe(true);
    expect(Object.keys(_test).sort()).toEqual([
      "SIGNING_KEY_RELPATH",
      "existingSigningKey",
      "gitSigningEnv",
      "signingConfigEntries",
      "signingPrivateKeyPath",
    ]);
  });

  test("SIGNING_KEY_RELPATH targets the private overlay keys directory", () => {
    expect(join(homedir(), _test.SIGNING_KEY_RELPATH)).toContain(
      join(".config", "dotfiles", "keys", "opencode-git-signing"),
    );
  });

  test("signingPrivateKeyPath resolves an existing key under HOME", () => {
    const temp = mkdtempSync(join(__dirname, "..", "git-signing-home-"));

    try {
      const keyPath = join(temp, _test.SIGNING_KEY_RELPATH);
      mkdirSync(join(keyPath, ".."), { recursive: true });
      writeFileSync(keyPath, "fake private key\n");

      expect(_test.signingPrivateKeyPath(temp)).toBe(keyPath);
    } finally {
      rmSync(temp, { force: true, recursive: true });
    }
  });

  test("signingPrivateKeyPath returns undefined without a key or with a directory", () => {
    const empty = mkdtempSync(join(__dirname, "..", "git-signing-empty-"));
    const dir = mkdtempSync(join(__dirname, "..", "git-signing-dir-"));
    mkdirSync(join(dir, _test.SIGNING_KEY_RELPATH), { recursive: true });

    try {
      expect(_test.signingPrivateKeyPath(empty)).toBeUndefined();
      expect(_test.signingPrivateKeyPath(dir)).toBeUndefined();
      expect(_test.signingPrivateKeyPath("")).toBeUndefined();
    } finally {
      rmSync(empty, { force: true, recursive: true });
      rmSync(dir, { force: true, recursive: true });
    }
  });

  test("signingConfigEntries forces ssh signing of commits and tags with the given key", () => {
    expect(_test.signingConfigEntries("/keys/opencode-git-signing")).toEqual([
      ["gpg.format", "ssh"],
      ["user.signingkey", "/keys/opencode-git-signing"],
      ["commit.gpgsign", "true"],
      ["tag.gpgsign", "true"],
    ]);
  });

  test("existingSigningKey finds a configured key and ignores foreign entries", () => {
    expect(
      _test.existingSigningKey({
        GIT_CONFIG_COUNT: "2",
        GIT_CONFIG_KEY_0: "core.pager",
        GIT_CONFIG_VALUE_0: "delta",
        GIT_CONFIG_KEY_1: "user.signingkey",
        GIT_CONFIG_VALUE_1: "/other/key",
      }),
    ).toBe("/other/key");

    expect(_test.existingSigningKey({})).toBeUndefined();
    expect(_test.existingSigningKey({ GIT_CONFIG_COUNT: "abc" })).toBeUndefined();
    expect(_test.existingSigningKey({ GIT_CONFIG_COUNT: "0" })).toBeUndefined();
    expect(
      _test.existingSigningKey({
        GIT_CONFIG_COUNT: "1",
        GIT_CONFIG_KEY_0: "core.pager",
        GIT_CONFIG_VALUE_0: "delta",
      }),
    ).toBeUndefined();
    expect(
      _test.existingSigningKey({
        GIT_CONFIG_COUNT: "1",
        GIT_CONFIG_KEY_0: "user.signingkey",
      }),
    ).toBeUndefined();
  });

  test("gitSigningEnv appends four config entries to a fresh environment", () => {
    expect(_test.gitSigningEnv("/keys/opencode-git-signing", {})).toEqual({
      GIT_CONFIG_COUNT: "4",
      GIT_CONFIG_KEY_0: "gpg.format",
      GIT_CONFIG_VALUE_0: "ssh",
      GIT_CONFIG_KEY_1: "user.signingkey",
      GIT_CONFIG_VALUE_1: "/keys/opencode-git-signing",
      GIT_CONFIG_KEY_2: "commit.gpgsign",
      GIT_CONFIG_VALUE_2: "true",
      GIT_CONFIG_KEY_3: "tag.gpgsign",
      GIT_CONFIG_VALUE_3: "true",
    });
  });

  test("gitSigningEnv offsets after pre-existing GIT_CONFIG entries", () => {
    const env = {
      GIT_CONFIG_COUNT: "2",
      GIT_CONFIG_KEY_0: "core.pager",
      GIT_CONFIG_VALUE_0: "delta",
      GIT_CONFIG_KEY_1: "init.defaultBranch",
      GIT_CONFIG_VALUE_1: "main",
    };

    expect(_test.gitSigningEnv("/keys/opencode-git-signing", env)).toEqual({
      GIT_CONFIG_COUNT: "6",
      GIT_CONFIG_KEY_2: "gpg.format",
      GIT_CONFIG_VALUE_2: "ssh",
      GIT_CONFIG_KEY_3: "user.signingkey",
      GIT_CONFIG_VALUE_3: "/keys/opencode-git-signing",
      GIT_CONFIG_KEY_4: "commit.gpgsign",
      GIT_CONFIG_VALUE_4: "true",
      GIT_CONFIG_KEY_5: "tag.gpgsign",
      GIT_CONFIG_VALUE_5: "true",
    });
  });

  test("gitSigningEnv treats an unparseable count as a fresh environment", () => {
    const injected = _test.gitSigningEnv("/keys/opencode-git-signing", { GIT_CONFIG_COUNT: "NaN" });

    expect(injected).not.toBeNull();
    expect(injected!.GIT_CONFIG_COUNT).toBe("4");
    expect(injected!.GIT_CONFIG_KEY_0).toBe("gpg.format");
  });

  test("gitSigningEnv keeps a foreign signing key but appends ours later so ours wins", () => {
    const env = {
      GIT_CONFIG_COUNT: "1",
      GIT_CONFIG_KEY_0: "user.signingkey",
      GIT_CONFIG_VALUE_0: "/other/key",
    };

    const injected = _test.gitSigningEnv("/keys/opencode-git-signing", env);
    expect(injected).not.toBeNull();
    expect(injected!.GIT_CONFIG_VALUE_2).toBe("/keys/opencode-git-signing");
    expect(injected!.GIT_CONFIG_COUNT).toBe("5");
  });

  test("gitSigningEnv is a no-op when this exact key is already configured", () => {
    const env = {
      GIT_CONFIG_COUNT: "1",
      GIT_CONFIG_KEY_0: "user.signingkey",
      GIT_CONFIG_VALUE_0: "/keys/opencode-git-signing",
    };

    expect(_test.gitSigningEnv("/keys/opencode-git-signing", env)).toBeNull();
  });
});
