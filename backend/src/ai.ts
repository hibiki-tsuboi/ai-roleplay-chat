import { type AIProvider, type ChatMessage, isRecord, maxMessageLength } from "./chat";

export interface AIEnv {
  AI_PROVIDER?: string;
  OPENAI_API_KEY?: string;
  OPENAI_MODEL?: string;
  GEMINI_API_KEY?: string;
  GEMINI_MODEL?: string;
}

interface AIConfig {
  provider: AIProvider;
  apiKey: string;
  model: string;
}

export function resolveAIConfig(env: AIEnv, selectedProvider?: AIProvider): AIConfig | null {
  const provider = selectedProvider ?? env.AI_PROVIDER ?? "openai";
  if (provider !== "openai" && provider !== "gemini") return null;
  const apiKey = (provider === "gemini" ? env.GEMINI_API_KEY : env.OPENAI_API_KEY)?.trim();
  const model = (provider === "gemini" ? env.GEMINI_MODEL : env.OPENAI_MODEL)?.trim();
  return apiKey && model ? { provider, apiKey, model } : null;
}

export function fetchAI(config: AIConfig, messages: ChatMessage[], options: {
  instructions: string; schema?: Record<string, unknown>; maxOutputTokens?: number;
}): Promise<Response> {
  const gemini = config.provider === "gemini";
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (gemini) headers["x-goog-api-key"] = config.apiKey;
  else headers.Authorization = `Bearer ${config.apiKey}`;

  return fetch(gemini
    ? "https://generativelanguage.googleapis.com/v1beta/interactions"
    : "https://api.openai.com/v1/responses", {
    method: "POST",
    headers,
    body: JSON.stringify(gemini ? {
      model: config.model,
      system_instruction: options.instructions,
      response_format: options.schema ? { type: "text", mime_type: "application/json", schema: options.schema } : undefined,
      input: messages.map((message) => ({
        type: message.role === "user" ? "user_input" : "model_output",
        content: [{ type: "text", text: message.content }],
      })),
      store: false,
      generation_config: {
        max_output_tokens: options.maxOutputTokens ?? 800,
        thinking_level: config.model === "gemini-3.5-flash-lite" ? "minimal" : undefined,
        thinking_summaries: "none",
      },
    } : {
      model: config.model,
      instructions: options.instructions,
      text: options.schema ? { format: { type: "json_schema", name: "practice_evaluation", strict: true, schema: options.schema } } : undefined,
      input: messages,
      store: false,
      max_output_tokens: options.maxOutputTokens ?? 800,
      // Keep short chat replies within the token budget; omit for GPT-4.1 rollback.
      reasoning: config.model === "gpt-5.6-luna" ? { effort: "none" } : undefined,
    }),
    signal: AbortSignal.timeout(30_000),
  });
}

export function extractReply(value: unknown, provider: AIConfig["provider"]): string | null {
  if (!isRecord(value) || value.status !== "completed") return null;
  const gemini = provider === "gemini";
  const output = gemini ? value.steps : value.output;
  if (!Array.isArray(output)) return null;
  const parts: string[] = [];
  for (const item of output) {
    if (!isRecord(item) || !Array.isArray(item.content)) continue;
    if (gemini ? item.type !== "model_output" : item.type !== "message" || item.role !== "assistant") continue;
    for (const content of item.content) {
      if (isRecord(content) && content.type === (gemini ? "text" : "output_text")
        && typeof content.text === "string") {
        parts.push(content.text);
      }
    }
  }
  const text = parts.join("\n").trim();
  return text.length > 0 && text.length <= maxMessageLength ? text : null;
}
