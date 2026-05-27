import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { createHash, randomUUID } from "node:crypto";
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

type ChatRequest = {
  model?: string;
  messages?: ChatMessage[];
  stream?: boolean;
  tools?: unknown;
  tool_choice?: unknown;
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
    .replace(/<\/opencode_previous_tool_result>/gi, "&lt;/opencode_previous_tool_result&gt;");
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
    if (/<opencode_tool_calls/i.test(output)) {
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
  if (output.indexOf("<opencode_tool_calls", end + closeMarker.length) !== -1) {
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
  if (process.env.OPENCODE_CURSOR_AGENT_TRUST === "1") {
    args.push("--trust");
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

async function handleStreamingChat(response: ServerResponse, request: ChatRequest, prompt: string, toolContext?: ToolContext) {
  const model = normalizeModel(request.model);
  const id = `chatcmpl-${randomUUID()}`;
  const child = spawnCursorAgent(model, prompt, true);
  let buffer = "";
  let toolEnabledOutput = "";
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
  response.on("error", () => undefined);

  if (!toolContext) {
    sendSse(response, roleChunk(id, model));
  }

  const timeout = setTimeout(() => stopProcess(child), REQUEST_TIMEOUT_MS);
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
      const text = event.message?.content
        ?.map((part) => (part.type === "text" ? part.text ?? "" : ""))
        .join("") ?? "";
      if (text) {
        if (toolContext) {
          // Tool-aware streams are buffered until Cursor's full answer is known;
          // the output may be either plain text or a tool-call marker.
          toolEnabledOutput += text;
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
        let parsed: ParsedCursorOutput;
        try {
          parsed = parseCursorOutput(toolEnabledOutput, toolContext);
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
      } else {
        sendSse(response, completionChunk(id, model, "", "stop"));
      }
      response.write("data: [DONE]\n\n");
      response.end();
    }
  });
}

async function handleJsonChat(response: ServerResponse, request: ChatRequest, prompt: string, toolContext?: ToolContext) {
  response.on("error", () => undefined);
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
    if (event.is_error) {
      error(response, 502, event.result ?? "cursor agent reported an error");
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
        error(response, status, message);
        return;
      }
      if (parsed.kind === "tool_calls") {
        message = { role: "assistant", content: null, tool_calls: parsed.tool_calls };
        finishReason = "tool_calls";
      } else {
        message = { role: "assistant", content: parsed.content };
      }
    }

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
  let toolContext: ToolContext | undefined;
  try {
    toolContext = toolContextFromRequest(body.tools, body.tool_choice);
  } catch (err) {
    error(response, err instanceof BridgeHttpError ? err.status : 400, err instanceof Error ? err.message : "invalid tools request");
    return;
  }

  const unsupported = unsupportedMessage(body.messages, toolContext !== undefined);
  if (unsupported) {
    error(response, 400, unsupported);
    return;
  }
  if (!body.messages?.length) {
    error(response, 400, "missing chat messages");
    return;
  }
  let prompt: string;
  try {
    prompt = toolContext ? toolAwarePromptFromMessages(body.messages, toolContext) : promptFromMessages(body.messages);
  } catch (err) {
    const status = err instanceof BridgeHttpError ? err.status : 500;
    const message = err instanceof Error ? err.message : "failed to build cursor agent prompt";
    error(response, status, message);
    return;
  }
  if (!prompt) {
    error(response, 400, "missing chat messages");
    return;
  }

  if (body.stream) {
    await handleStreamingChat(response, body, prompt, toolContext);
  } else {
    await handleJsonChat(response, body, prompt, toolContext);
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

/** @internal Test seam for pure helpers; not used by OpenCode at runtime. */
export const _test = Object.freeze({
  parsePositiveInteger,
  contentToText,
  deterministicToolCallId,
  finishChunk,
  roleChunk,
  unsupportedMessage,
  promptFromMessages,
  hasToolRequest,
  parseCursorOutput,
  normalizeModel,
  openAiUsage,
  sanitizeInboundContent,
  toolAwarePromptFromMessages,
  toolCallChunk,
  toolContextFromRequest,
  toolDefinitions,
  modelsResponse,
  healthResponse,
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

export default (async () => {
  // The Home Manager service owns the singleton HTTP listener. OpenCode
  // processes still load this file as a plugin, but they must not race to bind
  // the fixed provider port.
  return {};
}) satisfies Plugin;

if (import.meta.main && process.env.OPENCODE_CURSOR_AGENT_BRIDGE_STANDALONE === "1") {
  runStandalone();
}
