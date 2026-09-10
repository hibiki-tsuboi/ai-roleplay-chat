import { type Scenario, findScenario, scenarioInstructions } from "./scenarios";

export const maxMessages = 40;
export const maxMessageLength = 4_000;
export const maxTotalLength = 24_000;
export const practiceTurns = 5;
export const practiceMode = "five-turns";
export const maxPracticeLength = practiceTurns * 2 * maxMessageLength;

export type AIProvider = "openai" | "gemini";

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export interface ChatRequest {
  scenario: Scenario;
  provider?: AIProvider;
  messages: ChatMessage[];
  practice?: typeof practiceMode;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function parseChatRequest(value: unknown): ChatRequest | null {
  return parseRequest(value, false);
}

export function parseEvaluationRequest(value: unknown): ChatRequest | null {
  return parseRequest(value, true);
}

function parseRequest(value: unknown, evaluation: boolean): ChatRequest | null {
  if (!isRecord(value) || !Array.isArray(value.messages)) return null;
  const scenario = findScenario(value.scenarioId);
  if (!scenario) return null;
  if (value.messages.length < 1 || value.messages.length > maxMessages) return null;
  if (value.provider !== undefined && value.provider !== "openai" && value.provider !== "gemini") return null;
  if (value.practice !== undefined && value.practice !== practiceMode) return null;
  const practice = value.practice === practiceMode;
  if (evaluation && (!practice || value.provider === undefined)) return null;
  if (practice && (evaluation ? value.messages.length !== practiceTurns * 2
    : value.messages.length > practiceTurns * 2 - 1 || value.messages.length % 2 !== 1)) return null;

  const messages: ChatMessage[] = [];
  let totalLength = 0;
  for (const message of value.messages) {
    if (!isRecord(message)
      || (message.role !== "user" && message.role !== "assistant")
      || typeof message.content !== "string"
      || message.content.trim().length === 0
      || message.content.length > maxMessageLength) {
      return null;
    }
    totalLength += message.content.length;
    if (practice && message.role !== (messages.length % 2 === 0 ? "user" : "assistant")) return null;
    messages.push({ role: message.role, content: message.content });
  }
  if (totalLength > (practice ? maxPracticeLength : maxTotalLength)
    || messages.at(-1)?.role !== (evaluation ? "assistant" : "user")) return null;
  return { scenario, provider: value.provider, messages, practice: practice ? practiceMode : undefined };
}

export function chatInstructions(chat: ChatRequest): string {
  const base = scenarioInstructions(chat.scenario);
  if (!chat.practice) return base;
  const turn = (chat.messages.length + 1) / 2;
  return `${base}\nこの練習は全${practiceTurns}往復で、現在は${turn}往復目の返答です。これは進行の目安で、往復数・残り回数・練習の進め方を返答に書かないでください。\n${turn === practiceTurns
    ? "これが最後の返答です。上司の発言を受け止め、会話で合意した次の行動があれば短く確認して会話を締めてください。未合意の期限や行動を勝手に作らず、質問や新しい問題で会話を引き延ばさないでください。採点は別の評価者が行います。"
    : "上司が状況を聞き、次の行動を決められるように自然に応じてください。採点の説明はしないでください。"}`;
}
