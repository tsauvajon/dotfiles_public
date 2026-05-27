import { describe, expect, test } from "bun:test";

import { _test } from "../plugins/cursor-agent-bridge";

describe("cursor-agent-bridge pure helpers", () => {
  test("exposes the expected test seam", () => {
    expect(Object.isFrozen(_test)).toBe(true);
    expect(Object.keys(_test).sort()).toEqual([
      "contentToText",
      "healthResponse",
      "modelsResponse",
      "normalizeModel",
      "openAiUsage",
      "parsePositiveInteger",
      "promptFromMessages",
      "unsupportedMessage",
    ]);
  });

  test("parsePositiveInteger returns parsed positive integers or the fallback", () => {
    expect(_test.parsePositiveInteger(undefined, 7)).toBe(7);
    expect(_test.parsePositiveInteger("", 7)).toBe(7);
    expect(_test.parsePositiveInteger("42", 7)).toBe(42);
    // Preserve the current parseInt-style behavior until callers need stricter env parsing.
    expect(_test.parsePositiveInteger("12ms", 7)).toBe(12);
    expect(_test.parsePositiveInteger("0", 7)).toBe(7);
    expect(_test.parsePositiveInteger("-1", 7)).toBe(7);
    expect(_test.parsePositiveInteger("not-a-number", 7)).toBe(7);
  });

  test("contentToText converts supported content shapes to text", () => {
    expect(_test.contentToText("plain text")).toBe("plain text");
    expect(_test.contentToText({ text: "ignored" })).toBe("");
    expect(_test.contentToText([{ type: "image_url", image_url: {} }])).toBe("");
    expect(_test.contentToText([{ type: "image_url", text: "", image_url: { url: "https://example.com" } }])).toBe("");
    expect(
      _test.contentToText([{ type: "image_url", text: "alt text", image_url: { url: "https://example.com" } }]),
    ).toBe("alt text");
    expect(
      _test.contentToText([
        { type: "text", text: "first" },
        { type: "image_url", image_url: { url: "https://example.com/image.png" } },
        { type: "image_url", image_url: { url: "data:image/png;base64,abc" } },
        { type: "unknown" },
        null,
        "ignored",
        { text: "last" },
      ]),
    ).toBe("first\n[image: https://example.com/image.png]\n[image omitted]\nlast");
  });

  test("unsupportedMessage flags tool messages and tool calls", () => {
    expect(_test.unsupportedMessage(undefined)).toBeUndefined();
    expect(_test.unsupportedMessage([{ role: "user", content: "hello" }])).toBeUndefined();
    expect(_test.unsupportedMessage([{ role: "tool", content: "result" }])).toBe(
      "tool call messages are not supported by the cursor-agent bridge",
    );
    expect(_test.unsupportedMessage([{ role: "assistant", tool_calls: [] }])).toBe(
      "tool call messages are not supported by the cursor-agent bridge",
    );
  });

  test("promptFromMessages formats non-empty message content", () => {
    expect(_test.promptFromMessages(undefined)).toBe("");
    expect(_test.promptFromMessages([])).toBe("");
    expect(
      _test.promptFromMessages([
        { role: "system", content: " be concise " },
        { content: [{ type: "text", text: "hello" }] },
        { role: "assistant", content: "   " },
        { role: "assistant", content: "world" },
      ]),
    ).toBe("SYSTEM:\nbe concise\n\nUSER:\nhello\n\nASSISTANT:\nworld");
  });

  test("normalizeModel keeps supported models and falls back otherwise", () => {
    expect(_test.normalizeModel(undefined)).toBe("composer-2.5-fast");
    expect(_test.normalizeModel("")).toBe("composer-2.5-fast");
    expect(_test.normalizeModel("   ")).toBe("composer-2.5-fast");
    expect(_test.normalizeModel("composer-2.5")).toBe("composer-2.5");
    expect(_test.normalizeModel(" composer-2.5-fast ")).toBe("composer-2.5-fast");
    expect(_test.normalizeModel("unknown-model")).toBe("composer-2.5-fast");
  });

  test("openAiUsage converts cursor usage into OpenAI usage fields", () => {
    expect(_test.openAiUsage(undefined)).toEqual({
      prompt_tokens: 0,
      completion_tokens: 0,
      total_tokens: 0,
    });
    expect(
      _test.openAiUsage({
        inputTokens: 11,
        outputTokens: 13,
        cacheReadTokens: 17,
        cacheWriteTokens: 19,
      }),
    ).toEqual({
      prompt_tokens: 11,
      completion_tokens: 13,
      total_tokens: 24,
    });
  });

  test("modelsResponse returns the OpenAI-compatible model list", () => {
    expect(_test.modelsResponse()).toEqual({
      object: "list",
      data: [
        {
          id: "composer-2.5-fast",
          object: "model",
          created: 0,
          owned_by: "cursor-agent",
          name: "Composer 2.5 Fast",
        },
        {
          id: "composer-2.5",
          object: "model",
          created: 0,
          owned_by: "cursor-agent",
          name: "Composer 2.5",
        },
      ],
    });
  });

  test("healthResponse returns safe bridge diagnostics", () => {
    expect(_test.healthResponse()).toEqual({
      ok: true,
      pid: process.pid,
      host: "127.0.0.1",
      port: expect.any(Number),
      started_at: expect.any(String),
    });
  });
});
