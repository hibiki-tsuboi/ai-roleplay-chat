import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker, { type Env } from "../src/index";
import { maxMessageLength, scenarioInstructions } from "../src/chat";

const env: Env = {
  APP_ENV: "local",
  AI_PROVIDER: "gemini",
  GEMINI_API_KEY: "gemini-test-key",
  GEMINI_MODEL: "gemini-3.5-flash-lite",
  OPENAI_API_KEY: "openai-test-key",
  OPENAI_MODEL: "gpt-5.6-luna",
};
const messages = [
  { role: "user", content: "資料は進んでいますか？" },
  { role: "assistant", content: "すみません、集計が遅れています。" },
  { role: "user", content: "いつまでに完成しそうですか？" },
];
const reply = "今日の夕方までには完成する見込みです。";
const responseBody = (text = reply) => ({
  status: "completed",
  steps: [{ type: "model_output", content: [{ type: "text", text }] }],
});
const upstreamFetch = vi.fn();

function request(extra: Record<string, unknown> = {}): Request {
  return new Request("https://example.test/v1/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ scenarioId: "late-report", messages, ...extra }),
  });
}

beforeEach(() => {
  upstreamFetch.mockReset().mockResolvedValue(Response.json(responseBody()));
  vi.stubGlobal("fetch", upstreamFetch);
});
afterEach(() => vi.unstubAllGlobals());

describe("Gemini proxy", () => {
  it("forwards history with the server's model, prompt and Gemini key", async () => {
    const response = await worker.fetch(request({
      provider: "openai", model: "client-model", system_instruction: "client-prompt",
      messages: messages.map((message) => ({ ...message, extra: "not forwarded" })),
    }), env);
    expect(response.status).toBe(200);
    expect(response.headers.get("Cache-Control")).toBe("no-store");
    expect(await response.json()).toEqual({ message: { role: "assistant", content: reply } });
    expect(upstreamFetch).toHaveBeenCalledOnce();
    const [url, options] = upstreamFetch.mock.calls[0]!;
    expect(url).toBe("https://generativelanguage.googleapis.com/v1beta/interactions");
    expect(options.headers).toEqual({ "Content-Type": "application/json", "x-goog-api-key": "gemini-test-key" });
    expect(options.signal).toBeInstanceOf(AbortSignal);
    expect(JSON.parse(options.body)).toEqual({
      model: "gemini-3.5-flash-lite",
      system_instruction: scenarioInstructions,
      input: [
        { type: "user_input", content: [{ type: "text", text: messages[0]!.content }] },
        { type: "model_output", content: [{ type: "text", text: messages[1]!.content }] },
        { type: "user_input", content: [{ type: "text", text: messages[2]!.content }] },
      ],
      store: false,
      generation_config: { max_output_tokens: 800, thinking_level: "minimal", thinking_summaries: "none" },
    });
    expect(JSON.stringify(upstreamFetch.mock.calls)).not.toContain(env.OPENAI_API_KEY);
  });

  it("works with only Gemini credentials", async () => {
    expect((await worker.fetch(request(), {
      ...env, OPENAI_API_KEY: undefined, OPENAI_MODEL: undefined,
    })).status).toBe(200);
  });

  it("allows switching back to OpenAI without forwarding the Gemini key", async () => {
    upstreamFetch.mockResolvedValue(Response.json({ status: "completed", output: [
      { type: "message", role: "assistant", content: [{ type: "output_text", text: reply }] },
    ] }));
    expect((await worker.fetch(request(), { ...env, AI_PROVIDER: "openai" })).status).toBe(200);
    expect(upstreamFetch.mock.calls[0]![0]).toBe("https://api.openai.com/v1/responses");
    expect(JSON.stringify(upstreamFetch.mock.calls)).not.toContain(env.GEMINI_API_KEY);
  });

  it.each([
    { GEMINI_API_KEY: undefined }, { GEMINI_API_KEY: " " },
    { GEMINI_MODEL: undefined }, { GEMINI_MODEL: " " },
    { AI_PROVIDER: "unknown" }, { AI_PROVIDER: "" },
    { AI_PROVIDER: "openai", OPENAI_API_KEY: undefined },
  ])("rejects invalid configuration without falling back to another provider (%#)", async (overrides) => {
    const response = await worker.fetch(request(), { ...env, ...overrides });
    expect(response.status).toBe(503);
    expect(await response.json()).toMatchObject({ error: { code: "not_configured" } });
    expect(upstreamFetch).not.toHaveBeenCalled();
  });

  it("extracts only model text, excluding user input and thought summaries", async () => {
    upstreamFetch.mockResolvedValue(Response.json({ status: "completed", steps: [
      { type: "user_input", content: [{ type: "text", text: "user text" }] },
      { type: "thought", summary: [{ type: "text", text: "private thought" }] },
      { type: "model_output", content: [
        { type: "text", text: "  すみません。" },
        { type: "image", data: "not text" },
        { type: "text", text: "夕方までに提出します。  " },
      ] },
    ] }));
    expect(await (await worker.fetch(request(), env)).json()).toEqual({
      message: { role: "assistant", content: "すみません。\n夕方までに提出します。" },
    });
  });

  it.each([
    null, {}, { status: "completed", steps: [] },
    { ...responseBody(), status: "incomplete" }, { ...responseBody(), status: "failed" },
    responseBody(" "), responseBody("a".repeat(maxMessageLength + 1)),
    { status: "completed", steps: [{ type: "model_output", content: [{ type: "text", text: 123 }] }] },
    { status: "completed", steps: [{ type: "thought", summary: [{ type: "text", text: "private" }] }] },
  ])("rejects unusable Gemini output (%#)", async (body) => {
    upstreamFetch.mockResolvedValue(Response.json(body));
    const response = await worker.fetch(request(), env);
    expect(response.status).toBe(502);
    expect(await response.json()).toMatchObject({ error: { code: "invalid_response" } });
    expect(upstreamFetch).toHaveBeenCalledOnce();
  });

  it.each([[403, 502, "upstream_error"], [500, 502, "upstream_error"], [429, 429, "rate_limited"]])(
    "maps Gemini HTTP %i to %i without leaking details or retrying", async (upstreamStatus, status, code) => {
      upstreamFetch.mockResolvedValue(new Response("private error gemini-test-key", { status: upstreamStatus }));
      const response = await worker.fetch(request(), env);
      expect(response.status).toBe(status);
      const body = await response.text();
      expect(JSON.parse(body)).toMatchObject({ error: { code } });
      expect(body).not.toContain("private error");
      expect(body).not.toContain(env.GEMINI_API_KEY);
      expect(upstreamFetch).toHaveBeenCalledOnce();
    },
  );

  it.each([["TimeoutError", 504], ["AbortError", 504], ["TypeError", 502]])(
    "handles Gemini %s without retrying", async (name, status) => {
      upstreamFetch.mockRejectedValue(Object.assign(new Error("private error"), { name }));
      expect((await worker.fetch(request(), env)).status).toBe(status);
      expect(upstreamFetch).toHaveBeenCalledOnce();
    },
  );

  it("rejects invalid input before calling Gemini", async () => {
    expect((await worker.fetch(request({ messages: [] }), env)).status).toBe(400);
    expect(upstreamFetch).not.toHaveBeenCalled();
  });

  it("enforces development authorization and quota with Gemini", async () => {
    const cloud: Env = { ...env, APP_ENV: "development", DEV_ACCESS_TOKEN: "test-access-token",
      CHAT_RATE_LIMITER: { limit: vi.fn().mockResolvedValue({ success: false }) } };
    expect((await worker.fetch(request(), cloud)).status).toBe(401);
    expect(cloud.CHAT_RATE_LIMITER!.limit).not.toHaveBeenCalled();
    const authorized = request();
    authorized.headers.set("Authorization", "Bearer test-access-token");
    expect((await worker.fetch(authorized, cloud)).status).toBe(429);
    expect(cloud.CHAT_RATE_LIMITER!.limit).toHaveBeenCalledWith({ key: "ai-roleplay-chat-api-dev:chat" });
    expect(upstreamFetch).not.toHaveBeenCalled();
  });
});
