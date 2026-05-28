import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { createHash, randomUUID } from "node:crypto";
import { pathToFileURL } from "node:url";
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
const MAX_TOOL_MARKER_BYTES = 1024 * 1024;
const MAX_TOOL_AWARE_STREAM_BUFFER_BYTES = MAX_TOOL_MARKER_BYTES;
const TOOL_MARKER_PREFIX = "<opencode_tool_calls";
const REQUEST_ID_HEADER = "x-cursor-agent-bridge-request-id";
const RECENT_METRICS_LIMIT = parsePositiveInteger(process.env.OPENCODE_CURSOR_AGENT_METRICS_RECENT_LIMIT, 50);
const STARTED_AT = new Date().toISOString();

// Only the standalone service calls startBridge; this guard is defensive for
// tests or future entrypoints.
let started = false;
const activeChildren = new Set<ReturnType<typeof spawn>>();

type ChatMessage = {
  role?: string;
  content?: unknown;
  tool_call_id?: string;
  tool_calls?: unknown;
};

type ChatTool = {
  type?: string;
  function?: {
    name?: string;
    description?: string;
    parameters?: unknown;
  };
};

type ToolChoice =
  | string
  | {
      type?: string;
      function?: {
        name?: string;
      };
    };

type OpenAiToolCall = {
  id: string;
  type: "function";
  function: {
    name: string;
    arguments: string;
  };
};

type ToolDefinition = {
  name: string;
  description?: string;
  parameters?: unknown;
};

type ResolvedToolChoice =
  | { mode: "auto" }
  | { mode: "none" }
  | { mode: "required" }
  | { mode: "specific"; name: string };

type ToolContext = {
  nonce: string;
  tools: ToolDefinition[];
  toolNames: Set<string>;
  toolChoice: ResolvedToolChoice;
};

type ParsedCursorOutput =
  | { kind: "text"; content: string }
  | { kind: "tool_calls"; tool_calls: OpenAiToolCall[] };

type ToolAwareStreamState = {
  output: string;
  postFlushBuffer: string;
  textFlushed: boolean;
};

type ToolAwareStreamAction =
  | { kind: "buffer" }
  | { kind: "flush_text"; content: string }
  | { kind: "stream_text"; content: string }
  | { kind: "error"; message: string };

type ChatRequest = {
  model?: string;
  messages?: ChatMessage[];
  stream?: boolean;
  tools?: unknown;
  tool_choice?: unknown;
};

type CursorAgentBackend = "cli" | "sdk";

type CursorSdkModule = {
  Agent?: {
    prompt?: (prompt: string, options: CursorSdkOptions) => Promise<unknown> | unknown;
    create?: (options: CursorSdkOptions) => Promise<unknown> | unknown;
  };
  default?: {
    Agent?: CursorSdkModule["Agent"];
  };
};

type CursorSdkOptions = {
  apiKey: string;
  model: { id: string };
  local: { cwd: string };
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

type RequestContext = {
  requestId: string;
  startedAtMs: number;
  startedAt: string;
  backend?: CursorAgentBackend;
  model?: string;
  stream?: boolean;
  toolAware?: boolean;
  promptBytes?: number;
  finished: boolean;
};

type RecentRequest = {
  request_id: string;
  started_at: string;
  duration_ms: number;
  status: number;
  error: string | null;
  timed_out: boolean;
  backend?: CursorAgentBackend;
  model?: string;
  stream?: boolean;
  tool_aware?: boolean;
  prompt_bytes?: number;
};

type BackendRequestMetrics = {
  total: number;
  completed: number;
  failed: number;
  timed_out: number;
  active: number;
};

type MetricsState = {
  totalRequests: number;
  completedRequests: number;
  failedRequests: number;
  timedOutRequests: number;
  activeRequests: number;
  requestsByBackend: Record<CursorAgentBackend, BackendRequestMetrics>;
  recentRequests: RecentRequest[];
};

function emptyBackendMetrics(): BackendRequestMetrics {
  return {
    total: 0,
    completed: 0,
    failed: 0,
    timed_out: 0,
    active: 0,
  };
}

const metricsState: MetricsState = {
  totalRequests: 0,
  completedRequests: 0,
  failedRequests: 0,
  timedOutRequests: 0,
  activeRequests: 0,
  requestsByBackend: {
    cli: emptyBackendMetrics(),
    sdk: emptyBackendMetrics(),
  },
  recentRequests: [],
};

class BridgeHttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

class CursorTimeoutError extends BridgeHttpError {
  constructor(message = `cursor agent timed out after ${REQUEST_TIMEOUT_MS}ms`) {
    super(502, message);
  }
}

class ClientClosedError extends BridgeHttpError {
  constructor() {
    super(499, "client closed request");
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

function json(response: ServerResponse, status: number, body: unknown, headers: Record<string, string> = {}): void {
  response.writeHead(status, { "content-type": "application/json", ...headers });
  response.end(JSON.stringify(body));
}

function error(response: ServerResponse, status: number, message: string, headers: Record<string, string> = {}): void {
  if (response.headersSent) {
    if (!response.destroyed) {
      sendSse(response, { error: { message, type: "cursor_agent_bridge_error" } });
      response.write("data: [DONE]\n\n");
      response.end();
    }
    return;
  }
  json(response, status, { error: { message, type: "cursor_agent_bridge_error" } }, headers);
}

function requestHeaders(context: RequestContext): Record<string, string> {
  return { [REQUEST_ID_HEADER]: context.requestId };
}

function createRequestContext(): RequestContext {
  const now = Date.now();
  metricsState.totalRequests += 1;
  metricsState.activeRequests += 1;
  return {
    requestId: randomUUID(),
    startedAtMs: now,
    startedAt: new Date(now).toISOString(),
    finished: false,
  };
}

function finishRequest(
  context: RequestContext,
  status: number,
  message?: string,
  options: { timedOut?: boolean } = {},
): void {
  if (context.finished) {
    return;
  }
  context.finished = true;
  metricsState.activeRequests = Math.max(0, metricsState.activeRequests - 1);

  const failed = status >= 400 || message !== undefined;
  const backendMetrics = context.backend ? metricsState.requestsByBackend[context.backend] : undefined;
  if (backendMetrics) {
    backendMetrics.active = Math.max(0, backendMetrics.active - 1);
  }
  if (failed) {
    metricsState.failedRequests += 1;
    if (backendMetrics) {
      backendMetrics.failed += 1;
    }
  } else {
    metricsState.completedRequests += 1;
    if (backendMetrics) {
      backendMetrics.completed += 1;
    }
  }
  if (options.timedOut) {
    metricsState.timedOutRequests += 1;
    if (backendMetrics) {
      backendMetrics.timed_out += 1;
    }
  }

  metricsState.recentRequests.push({
    request_id: context.requestId,
    started_at: context.startedAt,
    duration_ms: Math.max(0, Date.now() - context.startedAtMs),
    status,
    error: message ?? null,
    timed_out: Boolean(options.timedOut),
    backend: context.backend,
    model: context.model,
    stream: context.stream,
    tool_aware: context.toolAware,
    prompt_bytes: context.promptBytes,
  });
  while (metricsState.recentRequests.length > RECENT_METRICS_LIMIT) {
    metricsState.recentRequests.shift();
  }
}

function setRequestBackend(context: RequestContext, backend: CursorAgentBackend): void {
  if (context.backend === backend) {
    return;
  }
  if (context.backend) {
    metricsState.requestsByBackend[context.backend].active = Math.max(
      0,
      metricsState.requestsByBackend[context.backend].active - 1,
    );
  }
  context.backend = backend;
  const backendMetrics = metricsState.requestsByBackend[backend];
  backendMetrics.total += 1;
  backendMetrics.active += 1;
}

function parseBody(request: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    let settled = false;
    request.setTimeout(60_000, () => {
      if (settled) {
        return;
      }
      settled = true;
      reject(new BridgeHttpError(408, "request body timeout"));
      request.destroy();
    });
    request.on("data", (chunk) => {
      if (settled) {
        return;
      }
      const buffer = Buffer.from(chunk);
      size += buffer.length;
      if (size > MAX_BODY_BYTES) {
        settled = true;
        reject(new BridgeHttpError(413, "request body too large"));
        request.destroy();
        return;
      }
      chunks.push(buffer);
    });
    request.on("error", (err) => {
      if (settled) {
        return;
      }
      settled = true;
      reject(err);
    });
    request.on("end", () => {
      if (settled) {
        return;
      }
      settled = true;
      request.setTimeout(0);
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

function hasToolRequest(tools: unknown): tools is ChatTool[] {
  return Array.isArray(tools) && tools.length > 0;
}

function unsupportedMessage(messages: ChatMessage[] | undefined, allowToolMessages = false): string | undefined {
  if (allowToolMessages) {
    return undefined;
  }
  const unsupported = messages?.find((message) => message.role === "tool" || message.tool_calls !== undefined);
  return unsupported ? "tool call messages are not supported by the cursor-agent bridge" : undefined;
}

function sanitizeInboundContent(content: string): string {
  return content
    .replace(/<opencode_tool_calls/gi, "&lt;opencode_tool_calls")
    .replace(/<\/opencode_tool_calls>/gi, "&lt;/opencode_tool_calls&gt;")
    .replace(/<opencode_previous_tool_calls/gi, "&lt;opencode_previous_tool_calls")
    .replace(/<\/opencode_previous_tool_calls>/gi, "&lt;/opencode_previous_tool_calls&gt;")
    .replace(/<opencode_previous_tool_result/gi, "&lt;opencode_previous_tool_result")
    .replace(/<\/opencode_previous_tool_result>/gi, "&lt;/opencode_previous_tool_result&gt;")
    .replace(/<system-reminder([^>]*)>/gi, "&lt;system-reminder$1&gt;")
    .replace(/<\/system-reminder>/gi, "&lt;/system-reminder&gt;")
    .replace(/<system-prompt([^>]*)>/gi, "&lt;system-prompt$1&gt;")
    .replace(/<\/system-prompt>/gi, "&lt;/system-prompt&gt;")
    .replace(/<environment_info([^>]*)>/gi, "&lt;environment_info$1&gt;")
    .replace(/<\/environment_info>/gi, "&lt;/environment_info&gt;");
}

function escapeAttribute(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
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

function toolDefinitions(tools: unknown): ToolDefinition[] {
  if (!hasToolRequest(tools)) {
    return [];
  }

  return tools.map((tool, index) => {
    if (!tool || typeof tool !== "object" || tool.type !== "function") {
      throw new BridgeHttpError(400, `tools[${index}] must be a function tool`);
    }
    const fn = tool.function;
    const name = fn?.name?.trim();
    if (!name) {
      throw new BridgeHttpError(400, `tools[${index}].function.name is required`);
    }
    return {
      name,
      description: fn?.description,
      parameters: fn?.parameters,
    };
  });
}

function resolveToolChoice(toolChoice: unknown, tools: ToolDefinition[]): ResolvedToolChoice {
  const names = new Set(tools.map((tool) => tool.name));
  if (toolChoice === undefined || toolChoice === null || toolChoice === "auto") {
    return { mode: "auto" };
  }
  if (toolChoice === "none") {
    return { mode: "none" };
  }
  if (toolChoice === "required") {
    return { mode: "required" };
  }
  if (typeof toolChoice === "object") {
    const choice = toolChoice as ToolChoice;
    const name = choice.type === "function" ? choice.function?.name?.trim() : undefined;
    if (!name) {
      throw new BridgeHttpError(400, "tool_choice function name is required");
    }
    if (!names.has(name)) {
      throw new BridgeHttpError(400, `tool_choice function '${name}' is not in tools`);
    }
    return { mode: "specific", name };
  }

  throw new BridgeHttpError(400, "unsupported tool_choice");
}

function toolContextFromRequest(tools: unknown, toolChoice: unknown, nonce = randomUUID()): ToolContext | undefined {
  if (!hasToolRequest(tools)) {
    if (toolChoice !== undefined && toolChoice !== null && toolChoice !== "auto") {
      throw new BridgeHttpError(400, "tool_choice requires at least one tool");
    }
    return undefined;
  }
  const definitions = toolDefinitions(tools);
  return {
    nonce,
    tools: definitions,
    toolNames: new Set(definitions.map((tool) => tool.name)),
    toolChoice: resolveToolChoice(toolChoice, definitions),
  };
}

function toolChoiceInstruction(toolChoice: ResolvedToolChoice): string {
  switch (toolChoice.mode) {
    case "none":
      return "tool_choice is none: do not emit a tool call marker; answer with text only.";
    case "required":
      return "tool_choice is required: you must emit a tool call marker instead of a text-only answer.";
    case "specific":
      return `tool_choice requires the function '${toolChoice.name}': emit exactly that function in the tool call marker.`;
    case "auto":
      return "tool_choice is auto: either answer with text or emit a tool call marker when a tool is needed.";
  }
}

function toolInstructions(context: ToolContext): string {
  const tools = context.tools
    .map((tool) => {
      const description = tool.description ? `\n  description: ${tool.description}` : "";
      const parameters = JSON.stringify(tool.parameters ?? {}, null, 2);
      return `- ${tool.name}${description}\n  parameters: ${parameters}`;
    })
    .join("\n");

  return [
    "SYSTEM:",
    "You can call OpenAI-compatible function tools by emitting a single live tool-call marker.",
    "These are OpenCode host tools, not Cursor Agent tools. Cursor Agent Ask-mode shell/file limitations do not apply to emitting this marker.",
    "Do not invoke Cursor-internal shell, file, edit, or terminal tools. Route workspace actions through the listed OpenCode tools instead.",
    "Never say shell access is blocked, ask the user to switch to Agent mode, or give the user commands to run when an available OpenCode tool can perform the requested action.",
    "If the user asks to run commands, edit files, inspect the workspace, commit, test, or use a named tool capability, emit a tool-call marker for the matching OpenCode tool instead of explaining that you cannot do it.",
    "When calling a tool, emit no prose outside the marker unless the user explicitly asks for an explanation after tool execution.",
    `Live marker format (nonce is mandatory and case-sensitive): <opencode_tool_calls nonce=\"${context.nonce}\">{\"tool_calls\":[{\"id\":\"optional\",\"type\":\"function\",\"function\":{\"name\":\"tool_name\",\"arguments\":\"{}\"}}]}</opencode_tool_calls>`,
    "The marker body must be valid JSON. function.arguments must be a JSON string; object arguments are also accepted and will be stringified by the bridge.",
    toolChoiceInstruction(context.toolChoice),
    "Available function tools:",
    tools,
  ].join("\n");
}

function serializePreviousToolCalls(toolCalls: unknown): string {
  if (!Array.isArray(toolCalls) || toolCalls.length === 0) {
    return "";
  }
  return `<opencode_previous_tool_calls>${sanitizeInboundContent(JSON.stringify(toolCalls))}</opencode_previous_tool_calls>`;
}

function serializeToolResult(message: ChatMessage): string {
  const content = sanitizeInboundContent(contentToText(message.content).trim());
  if (typeof message.tool_call_id !== "string" || !message.tool_call_id.trim()) {
    throw new BridgeHttpError(400, "tool result messages must include tool_call_id");
  }
  const toolCallId = escapeAttribute(message.tool_call_id.trim());
  return `<opencode_previous_tool_result tool_call_id="${toolCallId}">${content}</opencode_previous_tool_result>`;
}

function toolAwarePromptFromMessages(messages: ChatMessage[] | undefined, context: ToolContext): string {
  if (!messages?.length) {
    return toolInstructions(context);
  }

  const serializedMessages = messages
    .map((message) => {
      if (message.role === "tool") {
        return [`TOOL RESULT:`, serializeToolResult(message)].join("\n");
      }

      const role = message.role ?? "user";
      const content = sanitizeInboundContent(contentToText(message.content).trim());
      const text = content ? `${role.toUpperCase()}:\n${content}` : "";
      const previousToolCalls = message.role === "assistant" ? serializePreviousToolCalls(message.tool_calls) : "";
      return [text, previousToolCalls ? `ASSISTANT TOOL CALLS:\n${previousToolCalls}` : ""]
        .filter(Boolean)
        .join("\n\n");
    })
    .filter(Boolean)
    .join("\n\n");

  return [toolInstructions(context), serializedMessages].filter(Boolean).join("\n\n");
}

function normalizeModel(model: string | undefined): string {
  const requested = model?.trim() || DEFAULT_MODEL;
  return MODELS.has(requested) ? requested : DEFAULT_MODEL;
}

function requestedModel(model: string | undefined): string {
  return model?.trim() || DEFAULT_MODEL;
}

function resolveBackend(value = process.env.OPENCODE_CURSOR_AGENT_BACKEND): CursorAgentBackend {
  return value === "sdk" ? "sdk" : "cli";
}

function sdkModuleName(value = process.env.OPENCODE_CURSOR_AGENT_SDK_MODULE): string {
  return value?.trim() || "@cursor/sdk";
}

function sdkImportSpecifier(moduleName = sdkModuleName()): string {
  if (moduleName.startsWith("/")) {
    return pathToFileURL(moduleName).href;
  }
  return moduleName;
}

function sdkModelId(model: string | undefined, override = process.env.OPENCODE_CURSOR_AGENT_SDK_MODEL): string {
  return override?.trim() || normalizeModel(model);
}

function cursorSdkApiKey(): string {
  const apiKey = process.env.CURSOR_API_KEY?.trim();
  if (!apiKey) {
    throw new BridgeHttpError(500, "CURSOR_API_KEY is required when OPENCODE_CURSOR_AGENT_BACKEND=sdk");
  }
  return apiKey;
}

async function loadCursorSdk(): Promise<Required<Pick<CursorSdkModule, "Agent">>> {
  const module = (await import(sdkImportSpecifier())) as CursorSdkModule;
  const Agent = module.Agent ?? module.default?.Agent;
  if (!Agent) {
    throw new BridgeHttpError(502, `cursor sdk module '${sdkModuleName()}' does not export Agent`);
  }
  return { Agent };
}

function sdkAssistantText(event: unknown): string {
  if (!event || typeof event !== "object") {
    return "";
  }
  const message = (event as { message?: { role?: string; content?: unknown } }).message;
  if (!message || (message.role !== undefined && message.role !== "assistant")) {
    return "";
  }
  return sdkContentText(message.content);
}

function sdkContentText(content: unknown): string {
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
      const block = part as { type?: string; text?: unknown };
      return (block.type === "text" || block.type === undefined) && typeof block.text === "string" ? block.text : "";
    })
    .join("");
}

function sdkPromptResultText(result: unknown): string {
  if (typeof result === "string") {
    return result;
  }
  if (!result || typeof result !== "object") {
    return "";
  }
  const value = result as { result?: unknown; message?: { content?: unknown } };
  if (typeof value.result === "string") {
    return value.result;
  }
  return sdkContentText(value.message?.content);
}

function sdkEventError(event: unknown): string | undefined {
  if (!event || typeof event !== "object") {
    return undefined;
  }
  const value = event as { is_error?: boolean; error?: unknown; result?: unknown; message?: unknown };
  if (!value.is_error && value.error === undefined) {
    return undefined;
  }
  if (typeof value.result === "string") {
    return value.result;
  }
  if (typeof value.error === "string") {
    return value.error;
  }
  if (value.error && typeof value.error === "object" && typeof (value.error as { message?: unknown }).message === "string") {
    return (value.error as { message: string }).message;
  }
  return typeof value.message === "string" ? value.message : "cursor sdk reported an error";
}

function sdkUsage(result: unknown): CursorStreamEvent["usage"] | undefined {
  if (!result || typeof result !== "object") {
    return undefined;
  }
  const usage = (result as { usage?: CursorStreamEvent["usage"] }).usage;
  return usage && typeof usage === "object" ? usage : undefined;
}

function disposeCursorSdk(value: unknown): void {
  if (!value || typeof value !== "object") {
    return;
  }
  for (const method of ["cancel", "dispose", "close", "abort"] as const) {
    const candidate = (value as Record<string, unknown>)[method];
    if (typeof candidate === "function") {
      try {
        void Promise.resolve(candidate.call(value)).catch(() => undefined);
      } catch {
        // Cleanup is best-effort and must not mask the request failure path.
      }
      return;
    }
  }
}

function isAsyncIterable(value: unknown): value is AsyncIterable<unknown> {
  return Boolean(value && typeof value === "object" && typeof (value as AsyncIterable<unknown>)[Symbol.asyncIterator] === "function");
}

async function withCursorTimeout<T>(promise: Promise<T>, onTimeout: () => void): Promise<T> {
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<never>((_, reject) => {
        timeout = setTimeout(() => {
          onTimeout();
          reject(new CursorTimeoutError());
        }, REQUEST_TIMEOUT_MS);
      }),
    ]);
  } finally {
    if (timeout) {
      clearTimeout(timeout);
    }
  }
}

function responseClosed(response: ServerResponse): Promise<never> {
  return new Promise((_, reject) => {
    response.once("close", () => {
      if (!response.writableEnded) {
        reject(new ClientClosedError());
      }
    });
  });
}

async function runWithRequestLifecycle<T>(response: ServerResponse, promise: Promise<T>, cleanup: () => void): Promise<T> {
  return await Promise.race([
    withCursorTimeout(promise, cleanup),
    responseClosed(response).finally(cleanup),
  ]);
}

async function nextWithTimeout<T>(iterator: AsyncIterator<T>, cleanup: () => void): Promise<IteratorResult<T>> {
  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      iterator.next(),
      new Promise<never>((_, reject) => {
        timeout = setTimeout(() => {
          cleanup();
          reject(new CursorTimeoutError());
        }, REQUEST_TIMEOUT_MS);
      }),
    ]);
  } finally {
    if (timeout) {
      clearTimeout(timeout);
    }
  }
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

function stripCodeFence(value: string): string {
  const trimmed = value.trim();
  const match = trimmed.match(/^```(?:json)?\s*\n([\s\S]*?)\n```$/i);
  return match ? match[1].trim() : trimmed;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function deterministicToolCallId(name: string, args: string, index: number): string {
  const digest = createHash("sha256")
    .update(`${index}\0${name}\0${args}`)
    .digest("hex")
    .slice(0, 24);
  return `call_${digest}`;
}

function ensureJsonStringArguments(value: unknown, toolName: string): string {
  if (typeof value === "string") {
    try {
      JSON.parse(value);
    } catch {
      throw new BridgeHttpError(502, `tool call '${toolName}' arguments must be valid JSON`);
    }
    return value;
  }
  if (value && typeof value === "object") {
    return JSON.stringify(value);
  }
  throw new BridgeHttpError(502, `tool call '${toolName}' arguments must be a JSON string or object`);
}

function validateToolCall(call: unknown, index: number, context: ToolContext): OpenAiToolCall {
  if (!call || typeof call !== "object") {
    throw new BridgeHttpError(502, `tool_calls[${index}] must be an object`);
  }
  const candidate = call as { id?: unknown; type?: unknown; function?: { name?: unknown; arguments?: unknown } };
  if (candidate.type !== "function") {
    throw new BridgeHttpError(502, `tool_calls[${index}].type must be 'function'`);
  }
  const name = typeof candidate.function?.name === "string" ? candidate.function.name.trim() : "";
  if (!name) {
    throw new BridgeHttpError(502, `tool_calls[${index}].function.name is required`);
  }
  if (!context.toolNames.has(name)) {
    throw new BridgeHttpError(502, `tool call '${name}' is not available`);
  }
  if (context.toolChoice.mode === "none") {
    throw new BridgeHttpError(502, "tool_choice none forbids tool calls");
  }
  if (context.toolChoice.mode === "specific" && context.toolChoice.name !== name) {
    throw new BridgeHttpError(502, `tool_choice requires '${context.toolChoice.name}', not '${name}'`);
  }
  const args = ensureJsonStringArguments(candidate.function?.arguments, name);
  const id = typeof candidate.id === "string" && candidate.id.trim()
    ? candidate.id.trim()
    : deterministicToolCallId(name, args, index);
  return {
    id,
    type: "function",
    function: {
      name,
      arguments: args,
    },
  };
}

function extractToolCalls(value: unknown): unknown[] {
  if (value && typeof value === "object" && Array.isArray((value as { tool_calls?: unknown }).tool_calls)) {
    return (value as { tool_calls: unknown[] }).tool_calls;
  }
  throw new BridgeHttpError(502, "tool call marker JSON must contain a tool_calls array");
}

function parseCursorOutput(output: string, context: ToolContext): ParsedCursorOutput {
  const closeMarker = "</opencode_tool_calls>";
  const openMarker = new RegExp(`<opencode_tool_calls\\s+nonce=["']${escapeRegExp(context.nonce)}["']\\s*>`);
  const match = openMarker.exec(output);

  if (!match) {
    if (containsToolMarkerStart(output)) {
      throw new BridgeHttpError(502, "malformed tool call marker");
    }
    if (context.toolChoice.mode === "required") {
      throw new BridgeHttpError(502, "tool_choice required but cursor agent returned text");
    }
    if (context.toolChoice.mode === "specific") {
      throw new BridgeHttpError(502, `tool_choice requires '${context.toolChoice.name}' but cursor agent returned text`);
    }
    return { kind: "text", content: output };
  }

  const bodyStart = match.index + match[0].length;
  const end = output.indexOf(closeMarker, bodyStart);
  if (end === -1) {
    throw new BridgeHttpError(502, "tool call marker is missing its closing tag");
  }
  if (containsToolMarkerStart(output.slice(end + closeMarker.length))) {
    throw new BridgeHttpError(502, "multiple tool call markers are not supported");
  }

  const rawMarkerBody = output.slice(bodyStart, end);
  if (Buffer.byteLength(rawMarkerBody, "utf8") > MAX_TOOL_MARKER_BYTES) {
    throw new BridgeHttpError(502, "tool call marker is too large");
  }
  const markerBody = stripCodeFence(rawMarkerBody);
  let parsed: unknown;
  try {
    parsed = JSON.parse(markerBody);
  } catch {
    throw new BridgeHttpError(502, "tool call marker contains malformed JSON");
  }
  const rawToolCalls = extractToolCalls(parsed);
  if (rawToolCalls.length === 0) {
    throw new BridgeHttpError(502, "tool call marker must contain at least one tool call");
  }

  return {
    kind: "tool_calls",
    tool_calls: rawToolCalls.map((call, index) => validateToolCall(call, index, context)),
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

  const child = spawn(cursorCommand(), args, {
    cwd: process.cwd(),
    stdio: ["pipe", "pipe", "pipe"],
    env: cursorEnvironment(),
  });
  activeChildren.add(child);
  child.once("close", () => activeChildren.delete(child));

  child.stdout.setEncoding("utf8");
  child.stderr.setEncoding("utf8");
  child.stdin.end(`${prompt}\n`);
  return child;
}

function cursorEnvironment(): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {};
  for (const name of ["HOME", "PATH", "TMPDIR", "USER", "LOGNAME", "CURSOR_API_KEY"]) {
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

function stopActiveChildren(): void {
  for (const child of activeChildren) {
    stopProcess(child);
  }
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

function roleChunk(id: string, model: string) {
  return {
    ...completionChunk(id, model, "", null),
    choices: [{ index: 0, delta: { role: "assistant" }, finish_reason: null }],
  };
}

function toolCallChunk(id: string, model: string, toolCall: OpenAiToolCall, index: number) {
  const delta: {
    role?: "assistant";
    tool_calls: Array<{
      index: number;
      id: string;
      type: "function";
      function: { name: string; arguments: string };
    }>;
  } = {
    tool_calls: [
      {
        index,
        id: toolCall.id,
        type: "function",
        function: {
          name: toolCall.function.name,
          arguments: toolCall.function.arguments,
        },
      },
    ],
  };
  if (index === 0) {
    delta.role = "assistant";
  }

  return {
    id,
    object: "chat.completion.chunk",
    created: Math.floor(Date.now() / 1000),
    model,
    choices: [
      {
        index: 0,
        delta,
        finish_reason: null,
      },
    ],
  };
}

function finishChunk(id: string, model: string, finishReason: string) {
  return {
    ...completionChunk(id, model, "", finishReason),
    choices: [{ index: 0, delta: {}, finish_reason: finishReason }],
  };
}

function sendSse(response: ServerResponse, body: unknown): void {
  response.write(`data: ${JSON.stringify(body)}\n\n`);
}

function createToolAwareStreamState(): ToolAwareStreamState {
  return {
    output: "",
    postFlushBuffer: "",
    textFlushed: false,
  };
}

function isToolMarkerPrefix(value: string): boolean {
  return TOOL_MARKER_PREFIX.startsWith(value.toLowerCase());
}

function isToolMarkerBoundary(value: string | undefined): boolean {
  return value === ">" || (value !== undefined && /\s/.test(value));
}

function containsToolMarkerStart(value: string): boolean {
  const lower = value.toLowerCase();
  let offset = 0;
  while (offset < lower.length) {
    const index = lower.indexOf(TOOL_MARKER_PREFIX, offset);
    if (index === -1) {
      return false;
    }
    if (isToolMarkerBoundary(lower[index + TOOL_MARKER_PREFIX.length])) {
      return true;
    }
    offset = index + 1;
  }
  return false;
}

function shouldBufferUntilClose(toolChoice: ResolvedToolChoice): boolean {
  return toolChoice.mode === "required" || toolChoice.mode === "specific";
}

function toolAwareBufferTooLarge(value: string): boolean {
  return Buffer.byteLength(value, "utf8") > MAX_TOOL_AWARE_STREAM_BUFFER_BYTES;
}

function trailingToolMarkerPrefixLength(value: string): number {
  const lower = value.toLowerCase();
  const max = Math.min(lower.length, TOOL_MARKER_PREFIX.length);
  for (let length = max; length > 0; length -= 1) {
    if (TOOL_MARKER_PREFIX.startsWith(lower.slice(-length))) {
      return length;
    }
  }
  return 0;
}

function updateToolAwareStreamState(
  state: ToolAwareStreamState,
  text: string,
  toolChoice: ResolvedToolChoice,
): ToolAwareStreamAction {
  if (!text) {
    return { kind: "buffer" };
  }

  if (state.textFlushed) {
    const pending = state.postFlushBuffer + text;
    if (containsToolMarkerStart(pending)) {
      return { kind: "error", message: "tool call marker appeared after streaming text started" };
    }

    const keepLength = trailingToolMarkerPrefixLength(pending);
    const content = pending.slice(0, pending.length - keepLength);
    state.postFlushBuffer = pending.slice(pending.length - keepLength);
    return content ? { kind: "stream_text", content } : { kind: "buffer" };
  }

  state.output += text;

  if (shouldBufferUntilClose(toolChoice)) {
    if (toolAwareBufferTooLarge(state.output)) {
      return { kind: "error", message: "tool-aware streaming buffer is too large" };
    }
    return { kind: "buffer" };
  }

  if (containsToolMarkerStart(state.output)) {
    if (toolAwareBufferTooLarge(state.output)) {
      return { kind: "error", message: "tool-aware streaming buffer is too large" };
    }
    return { kind: "buffer" };
  }

  const firstNonWhitespace = state.output.trimStart();
  if (!firstNonWhitespace || isToolMarkerPrefix(firstNonWhitespace)) {
    if (toolAwareBufferTooLarge(state.output)) {
      return { kind: "error", message: "tool-aware streaming buffer is too large" };
    }
    return { kind: "buffer" };
  }
  const keepLength = trailingToolMarkerPrefixLength(state.output);
  if (keepLength > 0) {
    const content = state.output.slice(0, state.output.length - keepLength);
    if (!content) {
      return { kind: "buffer" };
    }
    state.textFlushed = true;
    state.postFlushBuffer = state.output.slice(state.output.length - keepLength);
    state.output = "";
    return { kind: "flush_text", content };
  }

  state.textFlushed = true;
  const content = state.output;
  state.output = "";
  return { kind: "flush_text", content };
}

function flushPendingToolAwareText(state: ToolAwareStreamState): string {
  const content = state.postFlushBuffer;
  state.postFlushBuffer = "";
  return content;
}

async function handleStreamingChat(
  response: ServerResponse,
  request: ChatRequest,
  prompt: string,
  requestContext: RequestContext,
  toolContext?: ToolContext,
) {
  const model = normalizeModel(request.model);
  requestContext.model = model;
  requestContext.stream = true;
  requestContext.toolAware = toolContext !== undefined;
  const id = `chatcmpl-${randomUUID()}`;
  const child = spawnCursorAgent(model, prompt, true);
  let buffer = "";
  const toolStreamState = createToolAwareStreamState();
  let failed = false;
  let timedOut = false;

  const fail = (message: string, options: { timedOut?: boolean } = {}) => {
    if (failed) {
      return;
    }
    failed = true;
    stopProcess(child);
    finishRequest(requestContext, 502, message, options);
    error(response, 502, message, requestHeaders(requestContext));
  };

  response.writeHead(200, {
    "content-type": "text/event-stream",
    "cache-control": "no-cache",
    connection: "keep-alive",
    ...requestHeaders(requestContext),
  });
  response.on("error", () => undefined);

  if (!toolContext) {
    sendSse(response, roleChunk(id, model));
  }

  // In tool-aware auto-mode, the bridge can only classify Cursor output before
  // any user-visible text is emitted. After text has been streamed, it must not
  // reinterpret the response as tool_calls; a real late marker becomes a bridge
  // error instead of leaking marker XML to the client.
  const processToolAwareText = (text: string) => {
    const action = updateToolAwareStreamState(toolStreamState, text, toolContext!.toolChoice);
    if (action.kind === "error") {
      fail(action.message);
      return;
    }
    if (action.kind === "flush_text") {
      sendSse(response, roleChunk(id, model));
      sendSse(response, completionChunk(id, model, action.content, null));
      return;
    }
    if (action.kind === "stream_text") {
      sendSse(response, completionChunk(id, model, action.content, null));
    }
  };

  const timeout = setTimeout(() => {
    timedOut = true;
    stopProcess(child);
  }, REQUEST_TIMEOUT_MS);
  requestAbortCleanup(response, child);

  child.on("error", (err) => fail(`failed to start cursor agent: ${err.message}`));
  const processStreamLine = (line: string) => {
    if (!line.trim()) {
      return;
    }
    let event: CursorStreamEvent;
    try {
      event = JSON.parse(line) as CursorStreamEvent;
    } catch {
      fail("cursor agent returned invalid stream json");
      return;
    }
    if (event.is_error) {
      fail(event.result ?? "cursor agent reported an error");
      return;
    }
    if (event.type === "assistant") {
      if (typeof event.timestamp_ms !== "number") {
        return;
      }
      const content = event.message?.content;
      if (content !== undefined && !Array.isArray(content)) {
        fail("cursor agent returned malformed assistant content");
        return;
      }
      const text = content?.map((part) => (part.type === "text" ? part.text ?? "" : "")).join("") ?? "";
      if (text) {
        if (toolContext) {
          processToolAwareText(text);
        } else {
          sendSse(response, completionChunk(id, model, text, null));
        }
      }
    }
  };
  child.stdout.on("data", (chunk: string) => {
    buffer += chunk;
    const lines = buffer.split("\n");
    buffer = lines.pop() ?? "";

    for (const line of lines) {
      processStreamLine(line);
      if (failed) {
        return;
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
    if (response.destroyed) {
      finishRequest(requestContext, 499, "client closed request");
      return;
    }
    if (timedOut) {
      fail(`cursor agent timed out after ${REQUEST_TIMEOUT_MS}ms`, { timedOut: true });
      return;
    }
    if (code !== 0) {
      fail(`cursor agent exited with code ${code}`);
      return;
    }
    if (!response.destroyed) {
      if (buffer.trim()) {
        processStreamLine(buffer);
        if (failed) {
          return;
        }
      }
      if (toolContext) {
        if (toolStreamState.textFlushed) {
          const pendingText = flushPendingToolAwareText(toolStreamState);
          if (pendingText) {
            sendSse(response, completionChunk(id, model, pendingText, null));
          }
          sendSse(response, finishChunk(id, model, "stop"));
        } else {
          let parsed: ParsedCursorOutput;
          try {
            parsed = parseCursorOutput(toolStreamState.output, toolContext);
          } catch (err) {
            fail(err instanceof Error ? err.message : "failed to parse cursor agent output");
            return;
          }
          if (parsed.kind === "tool_calls") {
            parsed.tool_calls.forEach((toolCall, index) => sendSse(response, toolCallChunk(id, model, toolCall, index)));
            sendSse(response, finishChunk(id, model, "tool_calls"));
          } else {
            sendSse(response, roleChunk(id, model));
            if (parsed.content) {
              sendSse(response, completionChunk(id, model, parsed.content, null));
            }
            sendSse(response, finishChunk(id, model, "stop"));
          }
        }
      } else {
        sendSse(response, completionChunk(id, model, "", "stop"));
      }
      finishRequest(requestContext, 200);
      response.write("data: [DONE]\n\n");
      response.end();
    }
  });
}

async function handleJsonChat(
  response: ServerResponse,
  request: ChatRequest,
  prompt: string,
  requestContext: RequestContext,
  toolContext?: ToolContext,
) {
  response.on("error", () => undefined);
  const model = normalizeModel(request.model);
  requestContext.model = model;
  requestContext.stream = false;
  requestContext.toolAware = toolContext !== undefined;
  const id = `chatcmpl-${randomUUID()}`;
  const child = spawnCursorAgent(model, prompt, false);
  const stdout: Buffer[] = [];
  let timedOut = false;
  const timeout = setTimeout(() => {
    timedOut = true;
    stopProcess(child);
  }, REQUEST_TIMEOUT_MS);
  let responded = false;

  child.stdout.on("data", (chunk) => stdout.push(Buffer.from(chunk)));
  child.stderr.on("data", () => undefined);
  child.on("error", (err) => {
    responded = true;
    clearTimeout(timeout);
    const message = `failed to start cursor agent: ${err.message}`;
    finishRequest(requestContext, 502, message);
    error(response, 502, message, requestHeaders(requestContext));
  });
  child.on("close", (code) => {
    if (responded) {
      return;
    }
    responded = true;
    clearTimeout(timeout);
    if (response.destroyed) {
      finishRequest(requestContext, 499, "client closed request");
      return;
    }
    if (timedOut) {
      const message = `cursor agent timed out after ${REQUEST_TIMEOUT_MS}ms`;
      finishRequest(requestContext, 502, message, { timedOut: true });
      error(response, 502, message, requestHeaders(requestContext));
      return;
    }
    if (code !== 0) {
      const message = `cursor agent exited with code ${code}`;
      finishRequest(requestContext, 502, message);
      error(response, 502, message, requestHeaders(requestContext));
      return;
    }

    const raw = Buffer.concat(stdout).toString("utf8");
    let event: CursorStreamEvent;
    try {
      event = JSON.parse(raw) as CursorStreamEvent;
    } catch {
      finishRequest(requestContext, 502, "cursor agent returned invalid json");
      error(response, 502, "cursor agent returned invalid json", requestHeaders(requestContext));
      return;
    }
    if (event.is_error) {
      const message = event.result ?? "cursor agent reported an error";
      finishRequest(requestContext, 502, message);
      error(response, 502, message, requestHeaders(requestContext));
      return;
    }
    const content = event.result ?? "";
    let message: { role: "assistant"; content: string | null; tool_calls?: OpenAiToolCall[] } = {
      role: "assistant",
      content,
    };
    let finishReason = "stop";
    if (toolContext) {
      let parsed: ParsedCursorOutput;
      try {
        parsed = parseCursorOutput(content, toolContext);
      } catch (err) {
        const status = err instanceof BridgeHttpError ? err.status : 502;
        const message = err instanceof Error ? err.message : "failed to parse cursor agent output";
        finishRequest(requestContext, status, message);
        error(response, status, message, requestHeaders(requestContext));
        return;
      }
      if (parsed.kind === "tool_calls") {
        message = { role: "assistant", content: null, tool_calls: parsed.tool_calls };
        finishReason = "tool_calls";
      } else {
        message = { role: "assistant", content: parsed.content };
      }
    }

    finishRequest(requestContext, 200);
    json(response, 200, {
      id,
      object: "chat.completion",
      created: Math.floor(Date.now() / 1000),
      model,
      choices: [
        {
          index: 0,
          message,
          finish_reason: finishReason,
        },
      ],
      usage: openAiUsage(event.usage),
    }, requestHeaders(requestContext));
  });
  requestAbortCleanup(response, child);
}

async function handleSdkJsonChat(
  response: ServerResponse,
  request: ChatRequest,
  prompt: string,
  requestContext: RequestContext,
  toolContext?: ToolContext,
) {
  response.on("error", () => undefined);
  const model = normalizeModel(request.model);
  const sdkModel = sdkModelId(request.model);
  requestContext.model = model;
  requestContext.stream = false;
  requestContext.toolAware = toolContext !== undefined;
  const id = `chatcmpl-${randomUUID()}`;

  let result: unknown;
  let agent: unknown;
  let run: unknown;
  let cleanup = () => undefined;
  try {
    const apiKey = cursorSdkApiKey();
    const sdk = await loadCursorSdk();
    let cleaned = false;
    cleanup = () => {
      if (cleaned) {
        return;
      }
      cleaned = true;
      disposeCursorSdk(run);
      disposeCursorSdk(agent);
    };

    if (typeof sdk.Agent.create === "function") {
      agent = await runWithRequestLifecycle(
        response,
        Promise.resolve(sdk.Agent.create({ apiKey, model: { id: sdkModel }, local: { cwd: process.cwd() } })),
        cleanup,
      );
      const send = agent && typeof agent === "object" ? (agent as { send?: unknown }).send : undefined;
      if (typeof send !== "function") {
        throw new BridgeHttpError(502, "cursor sdk Agent.create did not return an agent with send");
      }
      run = await runWithRequestLifecycle(response, Promise.resolve(send.call(agent, prompt)), cleanup);
      const wait = run && typeof run === "object" ? (run as { wait?: unknown }).wait : undefined;
      if (typeof wait !== "function") {
        throw new BridgeHttpError(502, "cursor sdk run does not expose wait");
      }
      result = await runWithRequestLifecycle(response, Promise.resolve(wait.call(run)), cleanup);
    } else {
      if (typeof sdk.Agent.prompt !== "function") {
        throw new BridgeHttpError(502, `cursor sdk module '${sdkModuleName()}' does not export Agent.create or Agent.prompt`);
      }
      // Agent.prompt has no run/agent handle to cancel. Keep it only as a compatibility fallback;
      // timeout/client-close handling can stop waiting, but cannot cancel the underlying SDK work.
      result = await runWithRequestLifecycle(
        response,
        Promise.resolve(
          sdk.Agent.prompt(prompt, {
            apiKey,
            model: { id: sdkModel },
            local: { cwd: process.cwd() },
          }),
        ),
        cleanup,
      );
    }
  } catch (err) {
    cleanup();
    const status = err instanceof BridgeHttpError ? err.status : 502;
    const message = err instanceof Error ? err.message : "cursor sdk request failed";
    finishRequest(requestContext, status, message, { timedOut: err instanceof CursorTimeoutError });
    if (!response.destroyed) {
      error(response, status, message, requestHeaders(requestContext));
    }
    return;
  } finally {
    cleanup();
  }

  const content = sdkPromptResultText(result);
  let message: { role: "assistant"; content: string | null; tool_calls?: OpenAiToolCall[] } = {
    role: "assistant",
    content,
  };
  let finishReason = "stop";
  if (toolContext) {
    let parsed: ParsedCursorOutput;
    try {
      parsed = parseCursorOutput(content, toolContext);
    } catch (err) {
      const status = err instanceof BridgeHttpError ? err.status : 502;
      const message = err instanceof Error ? err.message : "failed to parse cursor sdk output";
      finishRequest(requestContext, status, message);
      error(response, status, message, requestHeaders(requestContext));
      return;
    }
    if (parsed.kind === "tool_calls") {
      message = { role: "assistant", content: null, tool_calls: parsed.tool_calls };
      finishReason = "tool_calls";
    } else {
      message = { role: "assistant", content: parsed.content };
    }
  }

  finishRequest(requestContext, 200);
  json(response, 200, {
    id,
    object: "chat.completion",
    created: Math.floor(Date.now() / 1000),
    model,
    choices: [
      {
        index: 0,
        message,
        finish_reason: finishReason,
      },
    ],
    usage: openAiUsage(sdkUsage(result)),
  }, requestHeaders(requestContext));
}

async function handleSdkStreamingChat(
  response: ServerResponse,
  request: ChatRequest,
  prompt: string,
  requestContext: RequestContext,
  toolContext?: ToolContext,
) {
  const model = normalizeModel(request.model);
  const sdkModel = sdkModelId(request.model);
  requestContext.model = model;
  requestContext.stream = true;
  requestContext.toolAware = toolContext !== undefined;
  const id = `chatcmpl-${randomUUID()}`;
  const toolStreamState = createToolAwareStreamState();
  let agent: unknown;
  let run: unknown;
  let iterator: AsyncIterator<unknown> | undefined;
  let cleaned = false;
  const cleanup = () => {
    if (cleaned) {
      return;
    }
    cleaned = true;
    if (iterator && typeof iterator.return === "function") {
      try {
        void Promise.resolve(iterator.return()).catch(() => undefined);
      } catch {
        // Best-effort stream cleanup only.
      }
    }
    disposeCursorSdk(run);
    disposeCursorSdk(agent);
  };

  try {
    const apiKey = cursorSdkApiKey();
    const sdk = await loadCursorSdk();
    if (typeof sdk.Agent.create !== "function") {
      throw new BridgeHttpError(502, `cursor sdk module '${sdkModuleName()}' does not export Agent.create`);
    }
    agent = await runWithRequestLifecycle(
      response,
      Promise.resolve(sdk.Agent.create({ apiKey, model: { id: sdkModel }, local: { cwd: process.cwd() } })),
      cleanup,
    );
    const send = agent && typeof agent === "object" ? (agent as { send?: unknown }).send : undefined;
    if (typeof send !== "function") {
      throw new BridgeHttpError(502, "cursor sdk Agent.create did not return an agent with send");
    }
    run = await runWithRequestLifecycle(response, Promise.resolve(send.call(agent, prompt)), cleanup);
  } catch (err) {
    cleanup();
    const status = err instanceof BridgeHttpError ? err.status : 502;
    const message = err instanceof Error ? err.message : "cursor sdk request failed";
    finishRequest(requestContext, status, message, { timedOut: err instanceof CursorTimeoutError });
    if (!response.destroyed) {
      error(response, status, message, requestHeaders(requestContext));
    }
    return;
  }

  let stream: AsyncIterable<unknown>;
  try {
    const streamFactory = run && typeof run === "object" ? (run as { stream?: unknown }).stream : undefined;
    if (typeof streamFactory !== "function") {
      throw new BridgeHttpError(502, "cursor sdk run does not expose stream");
    }
    const candidate = await runWithRequestLifecycle(response, Promise.resolve(streamFactory.call(run)), cleanup);
    if (!isAsyncIterable(candidate)) {
      throw new BridgeHttpError(502, "cursor sdk run stream is not async iterable");
    }
    stream = candidate;
  } catch (err) {
    cleanup();
    const status = err instanceof BridgeHttpError ? err.status : 502;
    const message = err instanceof Error ? err.message : "cursor sdk stream setup failed";
    finishRequest(requestContext, status, message, { timedOut: err instanceof CursorTimeoutError });
    if (!response.destroyed) {
      error(response, status, message, requestHeaders(requestContext));
    }
    return;
  }

  let failed = false;
  const fail = (message: string, options: { timedOut?: boolean } = {}) => {
    if (failed) {
      return;
    }
    failed = true;
    cleanup();
    finishRequest(requestContext, 502, message, options);
    error(response, 502, message, requestHeaders(requestContext));
  };

  response.writeHead(200, {
    "content-type": "text/event-stream",
    "cache-control": "no-cache",
    connection: "keep-alive",
    ...requestHeaders(requestContext),
  });
  response.on("error", () => undefined);
  response.on("close", () => {
    if (!response.writableEnded && !failed) {
      failed = true;
      cleanup();
      finishRequest(requestContext, 499, "client closed request");
    }
  });

  if (!toolContext) {
    sendSse(response, roleChunk(id, model));
  }

  const processToolAwareText = (text: string) => {
    const action = updateToolAwareStreamState(toolStreamState, text, toolContext!.toolChoice);
    if (action.kind === "error") {
      fail(action.message);
      return;
    }
    if (action.kind === "flush_text") {
      sendSse(response, roleChunk(id, model));
      sendSse(response, completionChunk(id, model, action.content, null));
      return;
    }
    if (action.kind === "stream_text") {
      sendSse(response, completionChunk(id, model, action.content, null));
    }
  };

  try {
    iterator = stream[Symbol.asyncIterator]();
    while (!failed) {
      const next = await nextWithTimeout(iterator, cleanup);
      if (next.done) {
        break;
      }
      const event = next.value;
      if (failed) {
        break;
      }
      const eventError = sdkEventError(event);
      if (eventError) {
        fail(eventError);
        break;
      }
      const text = sdkAssistantText(event);
      if (!text) {
        continue;
      }
      if (toolContext) {
        processToolAwareText(text);
      } else {
        sendSse(response, completionChunk(id, model, text, null));
      }
    }
  } catch (err) {
    if (!failed) {
      fail(err instanceof Error ? err.message : "cursor sdk stream failed", { timedOut: err instanceof CursorTimeoutError });
    }
  } finally {
    cleanup();
  }

  if (failed || response.destroyed) {
    return;
  }

  if (toolContext) {
    if (toolStreamState.textFlushed) {
      const pendingText = flushPendingToolAwareText(toolStreamState);
      if (pendingText) {
        sendSse(response, completionChunk(id, model, pendingText, null));
      }
      sendSse(response, finishChunk(id, model, "stop"));
    } else {
      let parsed: ParsedCursorOutput;
      try {
        parsed = parseCursorOutput(toolStreamState.output, toolContext);
      } catch (err) {
        fail(err instanceof Error ? err.message : "failed to parse cursor sdk output");
        return;
      }
      if (parsed.kind === "tool_calls") {
        parsed.tool_calls.forEach((toolCall, index) => sendSse(response, toolCallChunk(id, model, toolCall, index)));
        sendSse(response, finishChunk(id, model, "tool_calls"));
      } else {
        sendSse(response, roleChunk(id, model));
        if (parsed.content) {
          sendSse(response, completionChunk(id, model, parsed.content, null));
        }
        sendSse(response, finishChunk(id, model, "stop"));
      }
    }
  } else {
    sendSse(response, completionChunk(id, model, "", "stop"));
  }
  finishRequest(requestContext, 200);
  response.write("data: [DONE]\n\n");
  response.end();
}

function requestAbortCleanup(response: ServerResponse, child: ReturnType<typeof spawn>): void {
  response.on("close", () => {
    if (!response.writableEnded) {
      stopProcess(child);
    }
  });
}

async function handleChat(request: IncomingMessage, response: ServerResponse): Promise<void> {
  const requestContext = createRequestContext();
  const backend = resolveBackend();
  setRequestBackend(requestContext, backend);
  const fail = (status: number, message: string) => {
    finishRequest(requestContext, status, message);
    error(response, status, message, requestHeaders(requestContext));
  };

  let body: ChatRequest;
  try {
    body = await parseBody(request) as ChatRequest;
  } catch (err) {
    if (err instanceof BridgeHttpError) {
      fail(err.status, err.message);
      return;
    }
    fail(400, "invalid json request body");
    return;
  }
  requestContext.model = normalizeModel(body.model);
  requestContext.stream = Boolean(body.stream);

  let toolContext: ToolContext | undefined;
  try {
    toolContext = toolContextFromRequest(body.tools, body.tool_choice);
  } catch (err) {
    fail(err instanceof BridgeHttpError ? err.status : 400, err instanceof Error ? err.message : "invalid tools request");
    return;
  }
  requestContext.toolAware = toolContext !== undefined;

  const unsupported = unsupportedMessage(body.messages, toolContext !== undefined);
  if (unsupported) {
    fail(400, unsupported);
    return;
  }
  if (!body.messages?.length) {
    fail(400, "missing chat messages");
    return;
  }
  let prompt: string;
  try {
    prompt = toolContext ? toolAwarePromptFromMessages(body.messages, toolContext) : promptFromMessages(body.messages);
  } catch (err) {
    const status = err instanceof BridgeHttpError ? err.status : 500;
    const message = err instanceof Error ? err.message : "failed to build cursor agent prompt";
    fail(status, message);
    return;
  }
  requestContext.promptBytes = Buffer.byteLength(prompt, "utf8");
  if (!prompt) {
    fail(400, "missing chat messages");
    return;
  }

  if (backend === "sdk") {
    if (body.stream) {
      await handleSdkStreamingChat(response, body, prompt, requestContext, toolContext);
    } else {
      await handleSdkJsonChat(response, body, prompt, requestContext, toolContext);
    }
  } else if (body.stream) {
    await handleStreamingChat(response, body, prompt, requestContext, toolContext);
  } else {
    await handleJsonChat(response, body, prompt, requestContext, toolContext);
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

function healthResponse() {
  return {
    ok: true,
    pid: process.pid,
    host: HOST,
    port: PORT,
    started_at: STARTED_AT,
  };
}

function metricsResponse() {
  return {
    ok: true,
    pid: process.pid,
    started_at: STARTED_AT,
    backend: resolveBackend(),
    active_children: activeChildren.size,
    active_requests: metricsState.activeRequests,
    requests: {
      total: metricsState.totalRequests,
      completed: metricsState.completedRequests,
      failed: metricsState.failedRequests,
      timed_out: metricsState.timedOutRequests,
    },
    requests_by_backend: {
      cli: { ...metricsState.requestsByBackend.cli },
      sdk: { ...metricsState.requestsByBackend.sdk },
    },
    recent_requests: metricsState.recentRequests.map((request) => ({ ...request })),
  };
}

/** @internal Test seam for pure helpers; not used by OpenCode at runtime. */
const testHelpers = Object.freeze({
  parsePositiveInteger,
  contentToText,
  cursorEnvironment,
  createToolAwareStreamState,
  deterministicToolCallId,
  finishChunk,
  flushPendingToolAwareText,
  roleChunk,
  unsupportedMessage,
  promptFromMessages,
  hasToolRequest,
  parseCursorOutput,
  normalizeModel,
  requestedModel,
  resolveBackend,
  sdkAssistantText,
  sdkContentText,
  sdkEventError,
  sdkImportSpecifier,
  sdkModelId,
  sdkModuleName,
  sdkPromptResultText,
  openAiUsage,
  sanitizeInboundContent,
  toolAwarePromptFromMessages,
  toolCallChunk,
  toolContextFromRequest,
  toolDefinitions,
  updateToolAwareStreamState,
  modelsResponse,
  healthResponse,
  metricsResponse,
});

function startBridge(options: { exitOnListenError?: boolean } = {}): ReturnType<typeof createServer> | undefined {
  if (started) {
    return undefined;
  }

  const server = createServer((request, response) => {
    const url = request.url ?? "/";
    if (request.method === "GET" && (url === "/health" || url === "/v1/health")) {
      json(response, 200, healthResponse());
      return;
    }
    if (request.method === "GET" && (url === "/models" || url === "/v1/models")) {
      json(response, 200, modelsResponse());
      return;
    }
    if (request.method === "GET" && (url === "/metrics" || url === "/v1/metrics")) {
      json(response, 200, metricsResponse());
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
      console.error(`cursor-agent bridge port ${HOST}:${PORT} is already in use`);
      if (options.exitOnListenError) {
        process.exit(1);
      }
      return;
    }
    console.error(`cursor-agent bridge failed to start: ${err.message}`);
    if (options.exitOnListenError) {
      process.exit(1);
    }
  });
  server.on("listening", () => {
    started = true;
  });
  server.listen(PORT, HOST);
  return server;
}

function runStandalone(): void {
  const server = startBridge({ exitOnListenError: true });
  if (!server) {
    process.exit(1);
  }

  const shutdown = () => {
    stopActiveChildren();
    const forcedExit = setTimeout(() => process.exit(0), 2_000);
    forcedExit.unref();
    server.close(() => {
      clearTimeout(forcedExit);
      process.exit(0);
    });
  };

  process.once("SIGTERM", shutdown);
  process.once("SIGINT", shutdown);
}

const CursorAgentBridgePlugin = (async () => {
  // The Home Manager service owns the singleton HTTP listener. OpenCode
  // processes still load this file as a plugin, but they must not race to bind
  // the fixed provider port.
  return {};
}) satisfies Plugin;

Object.defineProperty(CursorAgentBridgePlugin, "_test", { value: testHelpers });

export default CursorAgentBridgePlugin as typeof CursorAgentBridgePlugin & { readonly _test: typeof testHelpers };

if (import.meta.main && process.env.OPENCODE_CURSOR_AGENT_BRIDGE_STANDALONE === "1") {
  runStandalone();
}
