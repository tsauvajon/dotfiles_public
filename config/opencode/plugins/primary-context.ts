import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { Plugin, PluginInput } from "@opencode-ai/plugin";

const SESSION_LOOKUP_TIMEOUT_MS = 1_000;
const rootSessionCache = new Map<string, boolean>();

function primaryContextPath(): string {
  if (process.env.OPENCODE_PRIMARY_CONTEXT_FILE) {
    return process.env.OPENCODE_PRIMARY_CONTEXT_FILE;
  }

  const configHome = process.env.XDG_CONFIG_HOME ?? join(process.env.HOME ?? "", ".config");
  return join(configHome, "opencode", "primary-context.md");
}

function readPrimaryContext(path = primaryContextPath()): string | undefined {
  try {
    const content = readFileSync(path, "utf8").trim();
    return content === "" ? undefined : content;
  } catch {
    return undefined;
  }
}

async function isRootSession(
  client: PluginInput["client"],
  sessionID: string | undefined,
): Promise<boolean> {
  if (!sessionID) {
    return false;
  }

  const cached = rootSessionCache.get(sessionID);
  if (cached !== undefined) {
    return cached;
  }

  const response = await withTimeout(
    client.session.get({ path: { id: sessionID } }),
    SESSION_LOOKUP_TIMEOUT_MS,
  );
  const parentID = response?.data?.parentID;
  const isRoot = response?.data !== undefined && parentID == null;
  rootSessionCache.set(sessionID, isRoot);
  return isRoot;
}

function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T | undefined> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  return Promise.race([
    promise.catch(() => undefined),
    new Promise<undefined>((resolve) => {
      timer = setTimeout(() => resolve(undefined), timeoutMs);
    }),
  ]).finally(() => {
    if (timer !== undefined) {
      clearTimeout(timer);
    }
  });
}

const PrimaryContextPlugin = (async ({ client }) => ({
  "experimental.chat.system.transform": async ({ sessionID }, output) => {
    if (!(await isRootSession(client, sessionID))) {
      return;
    }

    const context = readPrimaryContext();
    if (context) {
      output.system.push(context);
    }
  },
})) satisfies Plugin;

const testHelpers = Object.freeze({
  isRootSession,
  primaryContextPath,
  readPrimaryContext,
});

Object.defineProperty(PrimaryContextPlugin, "_test", { value: testHelpers });

export default PrimaryContextPlugin as typeof PrimaryContextPlugin & { readonly _test: typeof testHelpers };
