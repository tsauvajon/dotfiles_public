import { accessSync, constants, existsSync, readFileSync, statSync } from "node:fs";
import { delimiter, dirname, join, resolve } from "node:path";
import type { Plugin, PluginInput } from "@opencode-ai/plugin";

const WORKSPACE_HEADER = /^\s*\[\s*workspace\s*\]\s*(?:#.*)?$/m;
const SCCACHE_CACHE_SIZE = "100G";
const SESSION_LOOKUP_TIMEOUT_MS = 1_000;
const rootSessionIdCache = new Map<string, string>();
const warnedNativeCompilerVars = new Set<string>();

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

async function targetSessionId(
  client: PluginInput["client"],
  sessionID: string | undefined,
): Promise<string> {
  const root = await rootSessionId(client, sessionID);
  return cacheSessionId(root) ?? `pid-${process.pid}`;
}

async function rootSessionId(
  client: PluginInput["client"],
  sessionID: string | undefined,
): Promise<string | undefined> {
  if (!sessionID) {
    return undefined;
  }

  const cached = rootSessionIdCache.get(sessionID);
  if (cached) {
    return cached;
  }

  const visited: string[] = [];
  let current = sessionID;

  for (let depth = 0; depth < 32; depth += 1) {
    if (visited.includes(current)) {
      return sessionID;
    }

    const cachedCurrent = rootSessionIdCache.get(current);
    if (cachedCurrent) {
      cacheVisitedSessions(visited, cachedCurrent);
      return cachedCurrent;
    }

    visited.push(current);

    const lookup = await getSession(client, current);
    if (!lookup.ok) {
      return sessionID;
    }

    if (!lookup.parentID) {
      cacheVisitedSessions(visited, current);
      return current;
    }

    current = lookup.parentID;
  }

  return sessionID;
}

async function getSession(client: PluginInput["client"], sessionID: string) {
  const response = await withTimeout(
    client.session.get({ path: { id: sessionID } }),
    SESSION_LOOKUP_TIMEOUT_MS,
  );
  if (!response?.data) {
    return { ok: false as const };
  }
  return { ok: true as const, parentID: response.data.parentID };
}

function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T | undefined> {
  return Promise.race([
    promise.catch(() => undefined),
    new Promise<undefined>((resolve) => setTimeout(() => resolve(undefined), timeoutMs)),
  ]);
}

function cacheVisitedSessions(sessionIDs: string[], rootID: string): void {
  for (const sessionID of sessionIDs) {
    rootSessionIdCache.set(sessionID, rootID);
  }
}

function setIfUnset(env: Record<string, string>, name: string, value: string): void {
  if (env[name] === undefined && process.env[name] === undefined) {
    env[name] = value;
  }
}

function warnForSccacheNativeCompilerVars(): void {
  for (const name of ["CC", "CXX"]) {
    const value = process.env[name];
    if (!value?.toLowerCase().includes("sccache") || warnedNativeCompilerVars.has(name)) {
      continue;
    }

    warnedNativeCompilerVars.add(name);
    console.warn(
      `[cargo-build-env] ${name}=${value} appears to use sccache. `
        + "Keep native compilers direct; cc-rs can already use RUSTC_WRAPPER=sccache and double-wrapping can fail.",
    );
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

export default (async ({ client }) => ({
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

    warnForSccacheNativeCompilerVars();

    if (output.env.CARGO_TARGET_DIR === undefined && process.env.CARGO_TARGET_DIR === undefined) {
      output.env.CARGO_TARGET_DIR = join(
        root,
        "target",
        "opencode",
        await targetSessionId(client, input.sessionID),
      );
    }

    if (process.env.HOME) {
      setIfUnset(
        output.env,
        "SCCACHE_DIR",
        join(process.env.HOME, ".cache", "sccache"),
      );
    }
    setIfUnset(output.env, "SCCACHE_CACHE_SIZE", SCCACHE_CACHE_SIZE);

    const sccache = commandPath("sccache");
    if (!sccache) {
      return;
    }

    setIfUnset(output.env, "RUSTC_WRAPPER", sccache);
  },
})) satisfies Plugin;
