import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { randomUUID } from "node:crypto";
import type { Plugin } from "@opencode-ai/plugin";

const HOST = "127.0.0.1";
const DEFAULT_PORT = 43115;
const PORT = parsePositiveInteger(process.env.OPENCODE_CURSOR_AGENT_BRIDGE_PORT, DEFAULT_PORT);
const DEFAULT_MODEL = "composer-2.5-fast";
const MODELS = new Map([
  ["composer-2.5-fast", "Composer 2.5 Fast"],
  ["composer-2.5", "Composer 2.5"],
]);
const REQUEST_TIMEOUT_MS = parsePositiveInteger(process.env.OPENCODE_CURSOR_AGENT_TIMEOUT_MS, 300_000);
const MAX_BODY_BYTES = parsePositiveInteger(process.env.OPENCODE_CURSOR_AGENT_MAX_BODY_BYTES, 16 * 1024 * 1024);

let started = false;

type ChatMessage = {
  role?: string;
  content?: unknown;
  tool_calls?: unknown;
};

type ChatRequest = {
  model?: string;
  messages?: ChatMessage[];
  stream?: boolean;
};

type CursorStreamEvent = {
  type?: string;
  subtype?: string;
  is_error?: boolean;
  result?: string;
  message?: {
    role?: string;
    content?: Array<{ type?: string; text?: string }>;
  };
  usage?: {
    inputTokens?: number;
    outputTokens?: number;
    cacheReadTokens?: number;
    cacheWriteTokens?: number;
  };
  timestamp_ms?: number;
};

class BridgeHttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

function parsePositiveInteger(value: string | undefined, fallback: number): number {
  if (!value) {
    return fallback;
  }
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function cursorCommand(): string {
  if (process.env.OPENCODE_CURSOR_AGENT_BIN) {
    return process.env.OPENCODE_CURSOR_AGENT_BIN;
  }

  const darwinCursor = "/Applications/Cursor.app/Contents/Resources/app/bin/cursor";
  if (process.platform === "darwin" && existsSync(darwinCursor)) {
    return darwinCursor;
  }

  return "cursor";
}

function json(response: ServerResponse, status: number, body: unknown): void {
  response.writeHead(status, { "content-type": "application/json" });
  response.end(JSON.stringify(body));
}

function error(response: ServerResponse, status: number, message: string): void {
  if (response.headersSent) {
    if (!response.destroyed) {
      sendSse(response, { error: { message, type: "cursor_agent_bridge_error" } });
      response.write("data: [DONE]\n\n");
      response.end();
    }
    return;
  }
  json(response, status, { error: { message, type: "cursor_agent_bridge_error" } });
}

function parseBody(request: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    request.setTimeout(60_000, () => {
      reject(new BridgeHttpError(408, "request body timeout"));
      request.destroy();
    });
    request.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
    request.on("data", (chunk) => {
      size += Buffer.byteLength(chunk);
      if (size > MAX_BODY_BYTES) {
        reject(new BridgeHttpError(413, "request body too large"));
        request.destroy();
      }
    });
    request.on("error", reject);
    request.on("end", () => {
      try {
        const raw = Buffer.concat(chunks).toString("utf8");
        resolve(raw.trim() ? JSON.parse(raw) : {});
      } catch (err) {
        reject(err);
      }
    });
  });
}

function contentToText(content: unknown): string {
  if (typeof content === "string") {
    return content;
  }
  if (!Array.isArray(content)) {
    return "";
  }

  return content
    .map((part) => {
      if (!part || typeof part !== "object") {
        return "";
      }
      const value = part as { type?: string; text?: string; image_url?: { url?: string } };
      if (typeof value.text === "string") {
        return value.text;
      }
      if (value.type === "image_url" && value.image_url?.url) {
        return value.image_url.url.startsWith("data:") ? "[image omitted]" : `[image: ${value.image_url.url}]`;
      }
      return "";
    })
    .filter(Boolean)
    .join("\n");
}

function unsupportedMessage(messages: ChatMessage[] | undefined): string | undefined {
  const unsupported = messages?.find((message) => message.role === "tool" || message.tool_calls !== undefined);
  return unsupported ? "tool call messages are not supported by the cursor-agent bridge" : undefined;
}

function promptFromMessages(messages: ChatMessage[] | undefined): string {
  if (!messages?.length) {
    return "";
  }

  return messages
    .map((message) => {
      const role = message.role ?? "user";
      const content = contentToText(message.content).trim();
      return content ? `${role.toUpperCase()}:\n${content}` : "";
    })
    .filter(Boolean)
    .join("\n\n");
}

function normalizeModel(model: string | undefined): string {
  const requested = model?.trim() || DEFAULT_MODEL;
  return MODELS.has(requested) ? requested : DEFAULT_MODEL;
}

function openAiUsage(usage: CursorStreamEvent["usage"] | undefined) {
  const promptTokens = usage?.inputTokens ?? 0;
  const completionTokens = usage?.outputTokens ?? 0;
  return {
    prompt_tokens: promptTokens,
    completion_tokens: completionTokens,
    total_tokens: promptTokens + completionTokens,
  };
}

function spawnCursorAgent(model: string, prompt: string, stream: boolean) {
  const args = [
    "agent",
    "--print",
    "--mode",
    "ask",
    "--model",
    model,
    "--output-format",
    stream ? "stream-json" : "json",
  ];
  if (stream) {
    args.push("--stream-partial-output");
  }
  if (process.env.OPENCODE_CURSOR_AGENT_TRUST === "1") {
    args.push("--trust");
  }

  const child = spawn(cursorCommand(), args, {
    cwd: process.cwd(),
    stdio: ["pipe", "pipe", "pipe"],
    env: cursorEnvironment(),
  });

  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdin.end(`${prompt}\n`);
  return child;
}

function cursorEnvironment(): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {};
  for (const name of ["HOME", "PATH", "SHELL", "TMPDIR", "USER", "LOGNAME", "CURSOR_API_KEY"]) {
    const value = process.env[name];
    if (value !== undefined) {
      env[name] = value;
    }
  }
  return env;
}

function stopProcess(child: ReturnType<typeof spawn>): void {
  if (child.exitCode !== null || child.signalCode !== null) {
    return;
  }
  child.kill("SIGTERM");
  setTimeout(() => {
    if (child.exitCode === null && child.signalCode === null) {
      child.kill("SIGKILL");
    }
  }, 2_000).unref();
}

function completionChunk(id: string, model: string, content: string, finishReason: string | null) {
  return {
    id,
    object: "chat.completion.chunk",
    created: Math.floor(Date.now() / 1000),
    model,
    choices: [
      {
        index: 0,
        delta: content ? { content } : {},
        finish_reason: finishReason,
      },
    ],
  };
}

function sendSse(response: ServerResponse, body: unknown): void {
  response.write(`data: ${JSON.stringify(body)}\n\n`);
}

async function handleStreamingChat(response: ServerResponse, request: ChatRequest, prompt: string) {
  const model = normalizeModel(request.model);
  const id = `chatcmpl-${randomUUID()}`;
  const child = spawnCursorAgent(model, prompt, true);
  let buffer = "";
  let failed = false;

  const fail = (message: string) => {
    if (failed) {
      return;
    }
    failed = true;
    stopProcess(child);
    error(response, 502, message);
  };

  response.writeHead(200, {
    "content-type": "text/event-stream",
    "cache-control": "no-cache",
    connection: "keep-alive",
  });

  sendSse(response, {
    ...completionChunk(id, model, "", null),
    choices: [{ index: 0, delta: { role: "assistant" }, finish_reason: null }],
  });

  const timeout = setTimeout(() => stopProcess(child), REQUEST_TIMEOUT_MS);
  requestAbortCleanup(response, child);

  child.on("error", (err) => fail(`failed to start cursor agent: ${err.message}`));
  child.stdout.on("data", (chunk: string) => {
    buffer += chunk;
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";

    for (const line of lines) {
      if (!line.trim()) {
        continue;
      }
      let event: CursorStreamEvent;
      try {
        event = JSON.parse(line) as CursorStreamEvent;
      } catch {
        fail("cursor agent returned invalid stream json");
        return;
      }
      if (event.type === "assistant") {
        if (typeof event.timestamp_ms !== "number") {
          continue;
        }
        const text = event.message?.content
          ?.map((part) => (part.type === "text" ? part.text ?? "" : ""))
          .join("") ?? "";
        if (text) {
          sendSse(response, completionChunk(id, model, text, null));
        }
      }
    }
  });

  child.stdout.on("error", () => undefined);
  child.stderr.on("data", () => undefined);
  child.on("close", (code) => {
    clearTimeout(timeout);
    if (failed) {
      return;
    }
    if (code !== 0) {
      fail(`cursor agent exited with code ${code}`);
      return;
    }
    if (!response.destroyed) {
      sendSse(response, completionChunk(id, model, "", "stop"));
      response.write("data: [DONE]\n\n");
      response.end();
    }
  });
}

async function handleJsonChat(response: ServerResponse, request: ChatRequest, prompt: string) {
  const model = normalizeModel(request.model);
  const id = `chatcmpl-${randomUUID()}`;
  const child = spawnCursorAgent(model, prompt, false);
  const stdout: Buffer[] = [];
  const timeout = setTimeout(() => stopProcess(child), REQUEST_TIMEOUT_MS);
  let responded = false;

  child.stdout.on("data", (chunk) => stdout.push(Buffer.from(chunk)));
  child.stderr.on("data", () => undefined);
  child.on("error", (err) => {
    responded = true;
    clearTimeout(timeout);
    error(response, 502, `failed to start cursor agent: ${err.message}`);
  });
  child.on("close", (code) => {
    if (responded) {
      return;
    }
    responded = true;
    clearTimeout(timeout);
    if (code !== 0) {
      error(response, 502, `cursor agent exited with code ${code}`);
      return;
    }

    const raw = Buffer.concat(stdout).toString("utf8");
    let event: CursorStreamEvent;
    try {
      event = JSON.parse(raw) as CursorStreamEvent;
    } catch {
      error(response, 502, "cursor agent returned invalid json");
      return;
    }
    json(response, 200, {
      id,
      object: "chat.completion",
      created: Math.floor(Date.now() / 1000),
      model,
      choices: [
        {
          index: 0,
          message: { role: "assistant", content: event.result ?? "" },
          finish_reason: "stop",
        },
      ],
      usage: openAiUsage(event.usage),
    });
  });
  requestAbortCleanup(response, child);
}

function requestAbortCleanup(response: ServerResponse, child: ReturnType<typeof spawn>): void {
  response.on("close", () => {
    if (!response.writableEnded) {
      stopProcess(child);
    }
  });
}

async function handleChat(request: IncomingMessage, response: ServerResponse): Promise<void> {
  let body: ChatRequest;
  try {
    body = await parseBody(request) as ChatRequest;
  } catch (err) {
    if (err instanceof BridgeHttpError) {
      error(response, err.status, err.message);
      return;
    }
    error(response, 400, "invalid json request body");
    return;
  }
  const unsupported = unsupportedMessage(body.messages);
  if (unsupported) {
    error(response, 400, unsupported);
    return;
  }
  const prompt = promptFromMessages(body.messages);
  if (!prompt) {
    error(response, 400, "missing chat messages");
    return;
  }

  if (body.stream) {
    await handleStreamingChat(response, body, prompt);
  } else {
    await handleJsonChat(response, body, prompt);
  }
}

function modelsResponse() {
  return {
    object: "list",
    data: [...MODELS].map(([id, name]) => ({
      id,
      object: "model",
      created: 0,
      owned_by: "cursor-agent",
      name,
    })),
  };
}

/** @internal Test seam for pure helpers; not used by OpenCode at runtime. */
export const _test = Object.freeze({
  parsePositiveInteger,
  contentToText,
  unsupportedMessage,
  promptFromMessages,
  normalizeModel,
  openAiUsage,
  modelsResponse,
});

function startBridge(): void {
  if (started) {
    return;
  }
  started = true;

  const server = createServer((request, response) => {
    const url = request.url ?? "/";
    if (request.method === "GET" && (url === "/health" || url === "/v1/health")) {
      json(response, 200, { ok: true });
      return;
    }
    if (request.method === "GET" && (url === "/models" || url === "/v1/models")) {
      json(response, 200, modelsResponse());
      return;
    }
    if (request.method === "POST" && (url === "/chat/completions" || url === "/v1/chat/completions")) {
      handleChat(request, response).catch(() => error(response, 500, "cursor agent bridge failed"));
      return;
    }
    error(response, 404, "not found");
  });

  server.on("error", (err: NodeJS.ErrnoException) => {
    if (err.code === "EADDRINUSE") {
      return;
    }
    console.warn(`cursor-agent bridge failed to start: ${err.message}`);
  });
  server.listen(PORT, HOST);
}

export default (async () => {
  startBridge();
  return {};
}) satisfies Plugin;
