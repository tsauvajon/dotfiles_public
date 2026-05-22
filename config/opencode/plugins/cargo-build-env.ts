import { accessSync, constants, existsSync, readFileSync, statSync } from "node:fs";
import { delimiter, dirname, join, resolve } from "node:path";
import type { Plugin } from "@opencode-ai/plugin";

const WORKSPACE_HEADER = /^\s*\[\s*workspace\s*\]\s*(?:#.*)?$/m;

function findCargoRoot(cwd: string): string | undefined {
  let dir = resolve(cwd);
  let nearestCargoRoot: string | undefined;

  while (true) {
    const manifest = join(dir, "Cargo.toml");
    if (existsSync(manifest)) {
      nearestCargoRoot ??= dir;
      if (isWorkspaceManifest(manifest)) {
        return dir;
      }
    }

    const parent = dirname(dir);
    if (parent === dir) {
      return nearestCargoRoot;
    }
    dir = parent;
  }
}

function isWorkspaceManifest(manifest: string): boolean {
  try {
    return WORKSPACE_HEADER.test(readFileSync(manifest, "utf8"));
  } catch {
    return false;
  }
}

function cacheSessionId(sessionID: string | undefined): string | undefined {
  const raw = [process.env.OPENCODE_RUN_ID, sessionID]
    .filter((value): value is string => Boolean(value))
    .join("-");
  return raw ? raw.replace(/[^A-Za-z0-9_.-]/g, "_").slice(0, 96) : undefined;
}

function targetSessionId(sessionID: string | undefined): string {
  return cacheSessionId(sessionID) ?? `pid-${process.pid}`;
}

function setIfUnset(env: Record<string, string>, name: string, value: string): void {
  if (env[name] === undefined && process.env[name] === undefined) {
    env[name] = value;
  }
}

function commandPath(name: string): string | undefined {
  return (process.env.PATH ?? "")
    .split(delimiter)
    .filter(Boolean)
    .map((dir) => join(dir, name))
    .find(isExecutable);
}

function isExecutable(path: string): boolean {
  try {
    if (!statSync(path).isFile()) {
      return false;
    }
    accessSync(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

export default (async () => ({
  "shell.env": async (input, output) => {
    if (process.platform !== "darwin") {
      return;
    }
    if (!input.cwd) {
      return;
    }

    const root = findCargoRoot(input.cwd);
    if (root === undefined) {
      return;
    }

    setIfUnset(
      output.env,
      "CARGO_TARGET_DIR",
      join(root, "target", "opencode", targetSessionId(input.sessionID)),
    );

    if (process.env.HOME) {
      setIfUnset(
        output.env,
        "SCCACHE_DIR",
        join(process.env.HOME, ".cache", "sccache"),
      );
    }

    const sccache = commandPath("sccache");
    if (!sccache) {
      return;
    }

    setIfUnset(output.env, "RUSTC_WRAPPER", sccache);
  },
})) satisfies Plugin;
