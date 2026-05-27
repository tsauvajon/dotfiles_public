import { afterAll, afterEach, describe, expect, test } from "bun:test";
import { spawn, type ChildProcess } from "node:child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const HOST = "127.0.0.1";
const REQUEST_ID_HEADER = "x-cursor-agent-bridge-request-id";
const bridgePath = fileURLToPath(new URL("../plugins/cursor-agent-bridge.ts", import.meta.url));
const CONTENT_TIMEOUT_MS = parseTestTimeout("OPENCODE_CURSOR_AGENT_BRIDGE_TEST_CONTENT_TIMEOUT_MS", 5_000);
const HEALTH_TIMEOUT_MS = parseTestTimeout("OPENCODE_CURSOR_AGENT_BRIDGE_TEST_HEALTH_TIMEOUT_MS", 10_000);
const tempDirs = new Set<string>();
const liveChildren = new Set<ChildProcess>();

type BridgeProcess = {
  child: ChildProcess;
  port: number;
  stderr: () => string;
};

type StartBridgeOptions = {
  attempts?: number;
  timeoutMs?: number;
};

describe("cursor-agent-bridge standalone HTTP streaming", () => {
  afterEach(async () => {
    await stopLiveChildren();
    cleanupTempDirs();
  });

  afterAll(async () => {
    await stopLiveChildren();
    cleanupTempDirs();
  });

  test("tool-aware streaming emits text before the cursor subprocess exits", async () => {
    const stub = createStub(`
await new Response(Bun.stdin.stream()).text();
emit("hello before close");
setInterval(() => {}, 1_000);
`);
    const bridge = await startBridge(stub);
    const controller = new AbortController();

    try {
      const response = await fetch(`http://${HOST}:${bridge.port}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(streamingToolRequest("answer with text")),
        signal: controller.signal,
      });

      expect(response.status).toBe(200);
      const content = await readFirstContentChunk(response, CONTENT_TIMEOUT_MS);
      expect(content).toBe("hello before close");
    } finally {
      controller.abort();
      await stopBridge(bridge.child);
    }
  });

  test("non-tool streaming preserves role, content, and stop chunks", async () => {
    const stub = createStub(`
await new Response(Bun.stdin.stream()).text();
emit("plain ");
emit("answer");
`);
    const bridge = await startBridge(stub);

    try {
      const response = await fetch(`http://${HOST}:${bridge.port}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(streamingTextRequest("answer without tools")),
      });

      expect(response.status).toBe(200);
      const events = parseSseEvents(await response.text());
      const roleIndex = events.findIndex((event) => event.choices?.[0]?.delta?.role === "assistant");
      const firstContentIndex = events.findIndex((event) => event.choices?.[0]?.delta?.content === "plain ");
      const secondContentIndex = events.findIndex((event) => event.choices?.[0]?.delta?.content === "answer");
      const stopIndex = events.findIndex((event) => event.choices?.[0]?.finish_reason === "stop");

      expect(roleIndex).toBeGreaterThanOrEqual(0);
      expect(firstContentIndex).toBeGreaterThan(roleIndex);
      expect(secondContentIndex).toBeGreaterThan(firstContentIndex);
      expect(stopIndex).toBeGreaterThan(secondContentIndex);
      expect(events.some((event) => event.error)).toBe(false);
      expect(events.some((event) => event.choices?.[0]?.delta?.tool_calls)).toBe(false);
    } finally {
      await stopBridge(bridge.child);
    }
  });

  test("streaming malformed assistant content returns an SSE error without crashing", async () => {
    const stub = createStub(`
await new Response(Bun.stdin.stream()).text();
process.stdout.write(JSON.stringify({
  type: "assistant",
  timestamp_ms: Date.now(),
  message: { role: "assistant", content: { type: "text", text: "bad" } },
}) + "\\n");
`);
    const bridge = await startBridge(stub);

    try {
      const response = await fetch(`http://${HOST}:${bridge.port}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(streamingTextRequest("return malformed content")),
      });

      expect(response.status).toBe(200);
      const events = parseSseEvents(await response.text());
      expect(events).toContainEqual({
        error: {
          message: "cursor agent returned malformed assistant content",
          type: "cursor_agent_bridge_error",
        },
      });
      expect(events.some((event) => event.choices?.[0]?.delta?.content !== undefined)).toBe(false);
      expect((await fetch(`http://${HOST}:${bridge.port}/health`)).ok).toBe(true);
    } finally {
      await stopBridge(bridge.child);
    }
  });

  test("streaming timeout reports a timeout SSE error", async () => {
    const timeoutMs = 100;
    const stub = createStub(`
await new Response(Bun.stdin.stream()).text();
setInterval(() => {}, 1_000);
`);
    const bridge = await startBridge(stub, { timeoutMs });

    try {
      const response = await fetch(`http://${HOST}:${bridge.port}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(streamingTextRequest("hang until timeout")),
      });

      expect(response.status).toBe(200);
      const events = parseSseEvents(await response.text());
      expect(events).toContainEqual({
        error: {
          message: `cursor agent timed out after ${timeoutMs}ms`,
          type: "cursor_agent_bridge_error",
        },
      });
      const requestId = response.headers.get(REQUEST_ID_HEADER);
      expect(requestId).toBeTruthy();
      const metrics = await fetchMetrics(bridge.port);
      const recent = metrics.recent_requests.find((entry: any) => entry.request_id === requestId);

      expect(metrics.active_requests).toBe(0);
      expect(metrics.requests).toMatchObject({ total: 1, completed: 0, failed: 1, timed_out: 1 });
      expect(recent).toMatchObject({
        request_id: requestId,
        model: "composer-2.5-fast",
        stream: true,
        status: 502,
        error: `cursor agent timed out after ${timeoutMs}ms`,
        timed_out: true,
      });
    } finally {
      await stopBridge(bridge.child);
    }
  });

  test("non-streaming JSON returns a text completion", async () => {
    const stub = createStub(`
await new Response(Bun.stdin.stream()).text();
process.stdout.write(JSON.stringify({
  result: "plain JSON answer",
  usage: { inputTokens: 2, outputTokens: 3 },
}));
`);
    const bridge = await startBridge(stub);

    try {
      const response = await fetch(`http://${HOST}:${bridge.port}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(nonStreamingTextRequest("answer without streaming")),
      });

      expect(response.status).toBe(200);
      const requestId = response.headers.get(REQUEST_ID_HEADER);
      expect(requestId).toBeTruthy();
      expect(await response.json()).toMatchObject({
        choices: [{ message: { role: "assistant", content: "plain JSON answer" }, finish_reason: "stop" }],
        usage: { prompt_tokens: 2, completion_tokens: 3, total_tokens: 5 },
      });
      const metrics = await fetchMetrics(bridge.port);
      const recent = metrics.recent_requests.find((entry: any) => entry.request_id === requestId);

      expect(metrics.active_requests).toBe(0);
      expect(metrics.requests).toMatchObject({ total: 1, completed: 1, failed: 0, timed_out: 0 });
      expect(recent).toMatchObject({
        request_id: requestId,
        model: "composer-2.5-fast",
        stream: false,
        tool_aware: false,
        status: 200,
        error: null,
        timed_out: false,
      });
      expect(recent.prompt_bytes).toBeGreaterThan(0);
      expect(recent.duration_ms).toBeGreaterThanOrEqual(0);
      expect(JSON.stringify(metrics)).not.toContain("answer without streaming");
      expect(JSON.stringify(metrics)).not.toContain("plain JSON answer");
    } finally {
      await stopBridge(bridge.child);
    }
  });

  test("non-streaming JSON reports cursor nonzero exits", async () => {
    const stub = createStub(`
await new Response(Bun.stdin.stream()).text();
process.exit(7);
`);
    const bridge = await startBridge(stub);

    try {
      const response = await fetch(`http://${HOST}:${bridge.port}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(nonStreamingTextRequest("fail without streaming")),
      });

      expect(response.status).toBe(502);
      expect(await response.json()).toEqual({
        error: { message: "cursor agent exited with code 7", type: "cursor_agent_bridge_error" },
      });
    } finally {
      await stopBridge(bridge.child);
    }
  });

  test("tool-aware streaming emits OpenAI tool_call chunks for a split marker", async () => {
    const stub = createStub(`
const prompt = await new Response(Bun.stdin.stream()).text();
const nonce = prompt.match(/<opencode_tool_calls nonce="([^"]+)">/)?.[1];
if (!nonce) {
  process.stderr.write("missing nonce in prompt\\n");
  process.exit(2);
}
emit("<opencode_tool");
emit('_calls nonce="' + nonce + '">{"tool_calls":[{"id":"call_stub","type":"function","function":{"name":"lookup_price","arguments":{"asset":"BTC"}}}]}</opencode_tool_calls>');
`);
    const bridge = await startBridge(stub);

    try {
      const response = await fetch(`http://${HOST}:${bridge.port}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(streamingToolRequest("call lookup_price for BTC")),
      });

      expect(response.status).toBe(200);
      const events = parseSseEvents(await response.text());
      const toolCallIndex = events.findIndex((event) => event.choices?.[0]?.delta?.tool_calls);
      const toolFinishIndex = events.findIndex((event) => event.choices?.[0]?.finish_reason === "tool_calls");

      expect(toolCallIndex).toBeGreaterThanOrEqual(0);
      expect(toolFinishIndex).toBeGreaterThan(toolCallIndex);
      expect(events.some((event) => event.choices?.[0]?.delta?.content !== undefined)).toBe(false);
      expect(events.some((event) => event.choices?.[0]?.finish_reason === "stop")).toBe(false);
      expect(events[toolCallIndex]).toMatchObject({
        choices: [
          {
            delta: {
              role: "assistant",
              tool_calls: [
                {
                  index: 0,
                  id: "call_stub",
                  type: "function",
                  function: { name: "lookup_price", arguments: '{"asset":"BTC"}' },
                },
              ],
            },
            finish_reason: null,
          },
        ],
      });
    } finally {
      await stopBridge(bridge.child);
    }
  });

  test("tool-aware none choice returns an SSE error for a real marker", async () => {
    const stub = createStub(`
const prompt = await new Response(Bun.stdin.stream()).text();
const nonce = prompt.match(/<opencode_tool_calls nonce="([^"]+)">/)?.[1];
if (!nonce) {
  process.stderr.write("missing nonce in prompt\\n");
  process.exit(2);
}
emit('<opencode_tool_calls nonce="' + nonce + '">{"tool_calls":[{"id":"call_forbidden","type":"function","function":{"name":"lookup_price","arguments":{"asset":"BTC"}}}]}</opencode_tool_calls>');
`);
    const bridge = await startBridge(stub);

    try {
      const response = await fetch(`http://${HOST}:${bridge.port}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(streamingToolRequest("do not call tools", "none")),
      });

      expect(response.status).toBe(200);
      const events = parseSseEvents(await response.text());
      expect(events).toContainEqual({
        error: {
          message: "tool_choice none forbids tool calls",
          type: "cursor_agent_bridge_error",
        },
      });
      expect(events.some((event) => event.choices?.[0]?.delta?.content !== undefined)).toBe(false);
      expect(events.some((event) => event.choices?.[0]?.finish_reason === "stop")).toBe(false);
    } finally {
      await stopBridge(bridge.child);
    }
  });

  test("tool-aware required choice emits tool_calls for a valid marker", async () => {
    const stub = createStub(`
const prompt = await new Response(Bun.stdin.stream()).text();
const nonce = prompt.match(/<opencode_tool_calls nonce="([^"]+)">/)?.[1];
if (!nonce) {
  process.stderr.write("missing nonce in prompt\\n");
  process.exit(2);
}
emit('<opencode_tool_calls nonce="' + nonce + '">{"tool_calls":[{"id":"call_required","type":"function","function":{"name":"lookup_price","arguments":{"asset":"ETH"}}}]}</opencode_tool_calls>');
`);
    const bridge = await startBridge(stub);

    try {
      const response = await fetch(`http://${HOST}:${bridge.port}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(streamingToolRequest("call lookup_price", "required")),
      });

      expect(response.status).toBe(200);
      assertSingleToolCallResponse(parseSseEvents(await response.text()), "call_required", '{"asset":"ETH"}');
    } finally {
      await stopBridge(bridge.child);
    }
  });

  test("tool-aware specific function choice emits tool_calls for a matching marker", async () => {
    const stub = createStub(`
const prompt = await new Response(Bun.stdin.stream()).text();
const nonce = prompt.match(/<opencode_tool_calls nonce="([^"]+)">/)?.[1];
if (!nonce) {
  process.stderr.write("missing nonce in prompt\\n");
  process.exit(2);
}
emit('<opencode_tool_calls nonce="' + nonce + '">{"tool_calls":[{"id":"call_specific","type":"function","function":{"name":"lookup_price","arguments":{"asset":"SOL"}}}]}</opencode_tool_calls>');
`);
    const bridge = await startBridge(stub);

    try {
      const response = await fetch(`http://${HOST}:${bridge.port}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(
          streamingToolRequest("call lookup_price", { type: "function", function: { name: "lookup_price" } }),
        ),
      });

      expect(response.status).toBe(200);
      assertSingleToolCallResponse(parseSseEvents(await response.text()), "call_specific", '{"asset":"SOL"}');
    } finally {
      await stopBridge(bridge.child);
    }
  });

  test("tool-aware required streaming returns an SSE error for text-only output", async () => {
    const stub = createStub(`
await new Response(Bun.stdin.stream()).text();
emit("plain text is not allowed here");
`);
    const bridge = await startBridge(stub);

    try {
      const response = await fetch(`http://${HOST}:${bridge.port}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(streamingToolRequest("call lookup_price for BTC", "required")),
      });

      expect(response.status).toBe(200);
      const events = parseSseEvents(await response.text());
      expect(events).toContainEqual({
        error: {
          message: "tool_choice required but cursor agent returned text",
          type: "cursor_agent_bridge_error",
        },
      });
      expect(events.some((event) => event.choices?.[0]?.delta?.content !== undefined)).toBe(false);
      expect(events.some((event) => event.choices?.[0]?.finish_reason === "stop")).toBe(false);
    } finally {
      await stopBridge(bridge.child);
    }
  });

  test("tool-aware streaming fails instead of forwarding a late marker after text", async () => {
    const stub = createStub(`
const prompt = await new Response(Bun.stdin.stream()).text();
const nonce = prompt.match(/<opencode_tool_calls nonce="([^"]+)">/)?.[1];
if (!nonce) {
  process.stderr.write("missing nonce in prompt\\n");
  process.exit(2);
}
emit("hello first");
emit('<opencode_tool_calls nonce="' + nonce + '">{"tool_calls":[{"id":"call_late","type":"function","function":{"name":"lookup_price","arguments":{"asset":"BTC"}}}]}</opencode_tool_calls>');
`);
    const bridge = await startBridge(stub);

    try {
      const response = await fetch(`http://${HOST}:${bridge.port}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(streamingToolRequest("answer then call a tool")),
      });

      expect(response.status).toBe(200);
      const events = parseSseEvents(await response.text());
      const contentIndex = events.findIndex((event) => event.choices?.[0]?.delta?.content === "hello first");
      const errorIndex = events.findIndex((event) => event.error?.message === "tool call marker appeared after streaming text started");

      expect(contentIndex).toBeGreaterThanOrEqual(0);
      expect(errorIndex).toBeGreaterThan(contentIndex);
      expect(events.some((event) => event.choices?.[0]?.delta?.content?.includes("<opencode_tool_calls"))).toBe(false);
      expect(events.some((event) => event.choices?.[0]?.delta?.tool_calls)).toBe(false);
    } finally {
      await stopBridge(bridge.child);
    }
  });

  test("tool-aware streaming returns an SSE error for a buffered malformed marker", async () => {
    const stub = createStub(`
const prompt = await new Response(Bun.stdin.stream()).text();
const nonce = prompt.match(/<opencode_tool_calls nonce="([^"]+)">/)?.[1];
if (!nonce) {
  process.stderr.write("missing nonce in prompt\\n");
  process.exit(2);
}
emit('<opencode_tool_calls nonce="' + nonce + '">{"tool_calls":[{"id":"call_missing_close","type":"function","function":{"name":"lookup_price","arguments":{"asset":"BTC"}}}]}');
`);
    const bridge = await startBridge(stub);

    try {
      const response = await fetch(`http://${HOST}:${bridge.port}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(streamingToolRequest("call lookup_price for BTC")),
      });

      expect(response.status).toBe(200);
      const events = parseSseEvents(await response.text());
      expect(events).toContainEqual({
        error: {
          message: "tool call marker is missing its closing tag",
          type: "cursor_agent_bridge_error",
        },
      });
      expect(events.some((event) => event.choices?.[0]?.delta?.content !== undefined)).toBe(false);
      expect(events.some((event) => event.choices?.[0]?.finish_reason === "stop")).toBe(false);
    } finally {
      await stopBridge(bridge.child);
    }
  });

  test("tool-aware streaming flushes a pending marker prefix on normal close after text", async () => {
    const stub = createStub(`
await new Response(Bun.stdin.stream()).text();
emit("hello first");
emit(" <opencode_tool");
`);
    const bridge = await startBridge(stub);

    try {
      const response = await fetch(`http://${HOST}:${bridge.port}/v1/chat/completions`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(streamingToolRequest("answer with a literal prefix")),
      });

      expect(response.status).toBe(200);
      const events = parseSseEvents(await response.text());
      const contentChunks = events
        .map((event) => event.choices?.[0]?.delta?.content)
        .filter((content): content is string => typeof content === "string");
      const stopIndex = events.findIndex((event) => event.choices?.[0]?.finish_reason === "stop");
      const lastContentIndex = events.findLastIndex((event) => event.choices?.[0]?.delta?.content !== undefined);

      expect(contentChunks.join("")).toBe("hello first <opencode_tool");
      expect(contentChunks.at(-1)).toBe("<opencode_tool");
      expect(stopIndex).toBeGreaterThan(lastContentIndex);
      expect(events.some((event) => event.error)).toBe(false);
      expect(events.some((event) => event.choices?.[0]?.delta?.tool_calls)).toBe(false);
    } finally {
      await stopBridge(bridge.child);
    }
  });
});

function createStub(body: string): string {
  const dir = mkdtempSync(join(tmpdir(), "cursor-agent-bridge-test-"));
  tempDirs.add(dir);
  const path = join(dir, "cursor-stub");
  writeFileSync(
    path,
    `#!/usr/bin/env bun
function emit(text) {
  process.stdout.write(JSON.stringify({
    type: "assistant",
    timestamp_ms: Date.now(),
    message: { role: "assistant", content: [{ type: "text", text }] },
  }) + "\\n");
}
${body}
`,
  );
  chmodSync(path, 0o755);
  return path;
}

async function startBridge(stub: string, options: StartBridgeOptions = {}): Promise<BridgeProcess> {
  const attempts = options.attempts ?? 3;
  let lastError: unknown;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      return await startBridgeOnce(stub, options);
    } catch (err) {
      lastError = err;
    }
  }
  throw lastError instanceof Error ? lastError : new Error("failed to start bridge");
}

async function startBridgeOnce(stub: string, options: StartBridgeOptions): Promise<BridgeProcess> {
  const port = await freePort();
  let stderr = "";
  const child = spawn(process.execPath, [bridgePath], {
    env: {
      ...process.env,
      OPENCODE_CURSOR_AGENT_BIN: stub,
      OPENCODE_CURSOR_AGENT_BRIDGE_PORT: String(port),
      OPENCODE_CURSOR_AGENT_BRIDGE_STANDALONE: "1",
      OPENCODE_CURSOR_AGENT_TIMEOUT_MS: String(options.timeoutMs ?? 30000),
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  liveChildren.add(child);
  child.stderr?.on("data", (chunk) => {
    stderr += String(chunk);
  });
  try {
    await waitForHealth(port, child, () => stderr);
  } catch (err) {
    await stopChild(child);
    throw err;
  }
  return { child, port, stderr: () => stderr };
}

async function stopBridge(child: ChildProcess): Promise<void> {
  try {
    await stopChild(child);
  } finally {
    cleanupTempDirs();
  }
}

async function stopChild(child: ChildProcess): Promise<void> {
  try {
    if (child.exitCode === null && child.signalCode === null) {
      child.kill("SIGTERM");
      await Promise.race([
        new Promise<void>((resolve) => child.once("close", () => resolve())),
        delay(2_000).then(() => {
          if (child.exitCode === null && child.signalCode === null) {
            child.kill("SIGKILL");
          }
        }),
      ]);
    }
  } finally {
    liveChildren.delete(child);
  }
}

async function stopLiveChildren(): Promise<void> {
  await Promise.all([...liveChildren].map((child) => stopBridge(child)));
}

function cleanupTempDirs(): void {
  for (const dir of tempDirs) {
    rmSync(dir, { recursive: true, force: true });
    tempDirs.delete(dir);
  }
}

function streamingTextRequest(content: string) {
  return {
    model: "composer-2.5-fast",
    stream: true,
    messages: [{ role: "user", content }],
  };
}

function nonStreamingTextRequest(content: string) {
  return {
    model: "composer-2.5-fast",
    stream: false,
    messages: [{ role: "user", content }],
  };
}

function streamingToolRequest(content: string, toolChoice: unknown = "auto") {
  return {
    model: "composer-2.5-fast",
    stream: true,
    messages: [{ role: "user", content }],
    tools: [
      {
        type: "function",
        function: {
          name: "lookup_price",
          description: "Lookup an asset price",
          parameters: { type: "object", properties: { asset: { type: "string" } }, required: ["asset"] },
        },
      },
    ],
    tool_choice: toolChoice,
  };
}

async function readFirstContentChunk(response: Response, timeoutMs: number): Promise<string> {
  const reader = response.body?.getReader();
  if (!reader) {
    throw new Error("missing response body");
  }
  const decoder = new TextDecoder();
  let buffer = "";
  const deadline = Date.now() + timeoutMs;

  while (Date.now() < deadline) {
    const remaining = Math.max(1, deadline - Date.now());
    const result = await Promise.race([reader.read(), delay(remaining).then(() => "timeout" as const)]);
    if (result === "timeout") {
      break;
    }
    if (result.done) {
      break;
    }
    buffer += decoder.decode(result.value, { stream: true });
    const completeEnd = buffer.lastIndexOf("\n\n");
    if (completeEnd === -1) {
      continue;
    }
    const complete = buffer.slice(0, completeEnd + 2);
    buffer = buffer.slice(completeEnd + 2);
    for (const event of parseSseEvents(complete)) {
      const content = event.choices?.[0]?.delta?.content;
      if (typeof content === "string" && content) {
        await reader.cancel().catch(() => undefined);
        return content;
      }
    }
  }

  throw new Error(`timed out waiting for streamed content; received: ${buffer}`);
}

function parseSseEvents(body: string): any[] {
  return body
    .split("\n\n")
    .flatMap((message) => message.split("\n"))
    .filter((line) => line.startsWith("data: "))
    .map((line) => line.slice("data: ".length).trim())
    .filter((data) => data && data !== "[DONE]")
    .map((data) => JSON.parse(data));
}

async function fetchMetrics(port: number): Promise<any> {
  const response = await fetch(`http://${HOST}:${port}/v1/metrics`);
  expect(response.status).toBe(200);
  return response.json();
}

function assertSingleToolCallResponse(events: any[], id: string, args: string): void {
  const toolCallIndex = events.findIndex((event) => event.choices?.[0]?.delta?.tool_calls);
  const toolFinishIndex = events.findIndex((event) => event.choices?.[0]?.finish_reason === "tool_calls");

  expect(toolCallIndex).toBeGreaterThanOrEqual(0);
  expect(toolFinishIndex).toBeGreaterThan(toolCallIndex);
  expect(events.some((event) => event.error)).toBe(false);
  expect(events.some((event) => event.choices?.[0]?.delta?.content !== undefined)).toBe(false);
  expect(events.some((event) => event.choices?.[0]?.finish_reason === "stop")).toBe(false);
  expect(events[toolCallIndex]).toMatchObject({
    choices: [
      {
        delta: {
          role: "assistant",
          tool_calls: [
            {
              index: 0,
              id,
              type: "function",
              function: { name: "lookup_price", arguments: args },
            },
          ],
        },
        finish_reason: null,
      },
    ],
  });
}

async function waitForHealth(port: number, child: ChildProcess, stderr: () => string): Promise<void> {
  const deadline = Date.now() + HEALTH_TIMEOUT_MS;
  while (Date.now() < deadline) {
    if (child.exitCode !== null || child.signalCode !== null) {
      throw new Error(`bridge exited before listening: ${stderr()}`);
    }
    try {
      const response = await fetch(`http://${HOST}:${port}/health`);
      if (response.ok) {
        return;
      }
    } catch {
      // Retry until the child binds the port.
    }
    await delay(50);
  }
  throw new Error(`bridge did not become healthy: ${stderr()}`);
}

function freePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once("error", reject);
    server.listen(0, HOST, () => {
      const address = server.address();
      if (!address || typeof address === "string") {
        reject(new Error("failed to allocate port"));
        return;
      }
      server.close(() => resolve(address.port));
    });
  });
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parseTestTimeout(name: string, fallback: number): number {
  const value = process.env[name];
  if (!value) {
    return fallback;
  }
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}
