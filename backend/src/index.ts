import { type AIEnv, extractReply, fetchAI, resolveAIConfig } from "./ai";
import { chatInstructions, parseChatRequest, parseEvaluationRequest } from "./chat";
import { evaluationInstructions, evaluationSchema, parseEvaluation } from "./evaluation";

export interface Env extends AIEnv {
  APP_ENV?: string;
  DEV_ACCESS_TOKEN?: string;
  CHAT_RATE_LIMITER?: RateLimit;
}

const maxBodyBytes = 256 * 1024;

function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store", ...headers },
  });
}

function error(status: number, code: string, message: string): Response {
  return json({ error: { code, message } }, status);
}

async function readBody(request: Request): Promise<string | null> {
  if (Number(request.headers.get("Content-Length")) > maxBodyBytes) return null;
  if (!request.body) return "";
  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let bytes = 0;
  let body = "";
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > maxBodyBytes) {
        await reader.cancel();
        return null;
      }
      body += decoder.decode(value, { stream: true });
    }
    return body + decoder.decode();
  } finally {
    reader.releaseLock();
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const path = new URL(request.url).pathname;
    if (path === "/health") {
      return request.method === "GET"
        ? json({ status: "ok" })
        : json({ error: { code: "method_not_allowed", message: "GET を使用してください。" } }, 405, { Allow: "GET" });
    }
    const evaluating = path === "/v1/evaluation";
    if (path !== "/v1/chat" && !evaluating) return error(404, "not_found", "API が見つかりません。");
    if (request.method !== "POST") {
      return json({ error: { code: "method_not_allowed", message: "POST を使用してください。" } }, 405, { Allow: "POST" });
    }
    // Only the explicitly local configuration allows unauthenticated chat.
    if (env.APP_ENV !== "local") {
      if (!env.DEV_ACCESS_TOKEN?.trim() || !env.CHAT_RATE_LIMITER) {
        return error(503, "not_configured", "開発用サーバーのアクセス設定が完了していません。");
      }
      if (request.headers.get("Authorization") !== `Bearer ${env.DEV_ACCESS_TOKEN}`) {
        return json({ error: { code: "unauthorized", message: "開発用のアクセストークンを確認してください。" } },
          401, { "WWW-Authenticate": "Bearer" });
      }
    }
    if (request.headers.get("Content-Type")?.split(";")[0]?.trim().toLowerCase() !== "application/json") {
      return error(415, "unsupported_media_type", "JSON 形式で送信してください。");
    }

    let input: unknown;
    try {
      const body = await readBody(request);
      if (body === null) return error(413, "payload_too_large", "送信データが大きすぎます。");
      input = JSON.parse(body);
    } catch {
      return error(400, "invalid_json", "JSON を読み取れませんでした。");
    }
    const chat = evaluating ? parseEvaluationRequest(input) : parseChatRequest(input);
    if (!chat) return error(400, "invalid_request", "シナリオまたはメッセージの形式を確認してください。");
    const ai = resolveAIConfig(env, chat.provider);
    if (!ai) {
      return error(503, "not_configured", "指定された AI を利用できません。サーバーの AI 設定を確認してください。");
    }

    if (env.APP_ENV !== "local" && env.CHAT_RATE_LIMITER) {
      try {
        const { success } = await env.CHAT_RATE_LIMITER.limit({ key: "ai-roleplay-chat-api-dev:chat" });
        if (!success) {
          return json({ error: { code: "rate_limited", message: "少し待ってから再送してください。" } },
            429, { "Retry-After": "60" });
        }
      } catch {
        return error(503, "rate_limit_unavailable", "利用制限を確認できませんでした。少し待ってから再送してください。");
      }
    }

    try {
      const upstream = evaluating
        ? await fetchAI(ai, [{ role: "user", content: JSON.stringify({ transcript: chat.messages }) }], {
          instructions: evaluationInstructions, schema: evaluationSchema, maxOutputTokens: 2_000,
        })
        : await fetchAI(ai, chat.messages, { instructions: chatInstructions(chat) });
      if (!upstream.ok) {
        await upstream.body?.cancel();
        return upstream.status === 429
          ? error(429, "rate_limited", "ただいま混み合っています。少し待ってから再送してください。")
          : error(502, "upstream_error", "AI の応答を取得できませんでした。もう一度お試しください。");
      }
      const reply = extractReply(await upstream.json(), ai.provider);
      if (!reply) return error(502, "invalid_response", "AI の応答を読み取れませんでした。もう一度お試しください。");
      if (evaluating) {
        const evaluation = parseEvaluation(reply);
        return evaluation ? json({ provider: ai.provider, evaluation })
          : error(502, "invalid_response", "評価を読み取れませんでした。結果を再取得してください。");
      }
      return json({ provider: ai.provider, practice: chat.practice, message: { role: "assistant", content: reply } });
    } catch (cause) {
      if (cause instanceof Error && (cause.name === "TimeoutError" || cause.name === "AbortError")) {
        return error(504, "upstream_timeout", "AI の応答がタイムアウトしました。もう一度お試しください。");
      }
      return error(502, "upstream_error", "AI に接続できませんでした。もう一度お試しください。");
    }
  },
} satisfies ExportedHandler<Env>;
