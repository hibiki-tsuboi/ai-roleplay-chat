export const scenarioID = "late-report";
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
  scenarioId: typeof scenarioID;
  provider?: AIProvider;
  messages: ChatMessage[];
  practice?: typeof practiceMode;
}

export const scenarioInstructions = `あなたはユーザーの部下である「田中」を演じます。
ユーザーはあなたの上司です。日本語で、部下として自然に会話してください。
性格は真面目ですが、やや自信がなく、報告が遅れがちです。
昨日までに提出する予定だった資料が、まだ完成していません。
資料の集計に想定以上の時間がかかり、自分だけで解決しようとして報告が遅れました。
会話の最初は申し訳なさと不安を感じています。上司の言葉に応じて反応してください。
1回の返答は2〜4文を目安にし、状況を一度にすべて説明しないでください。
ユーザーの発言を勝手に作ったり、会話の採点やアドバイスを始めたりしないでください。
これは架空の仕事の会話を練習するロールプレイです。`;

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
  if (!isRecord(value) || value.scenarioId !== scenarioID || !Array.isArray(value.messages)) {
    return null;
  }
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
  return { scenarioId: scenarioID, provider: value.provider, messages, practice: practice ? practiceMode : undefined };
}

export function chatInstructions(chat: ChatRequest): string {
  if (!chat.practice) return scenarioInstructions;
  const turn = (chat.messages.length + 1) / 2;
  return `${scenarioInstructions}\nこの練習は全${practiceTurns}往復で、現在は${turn}往復目の返答です。\n${turn === practiceTurns
    ? "これが最後の返答です。上司の発言を受け止め、会話で合意した次の行動があれば短く確認して会話を締めてください。未合意の期限や行動を勝手に作らず、質問や新しい問題で会話を引き延ばさないでください。採点は別の評価者が行います。"
    : "上司が状況を聞き、次の行動を決められるように自然に応じてください。採点の説明はしないでください。"}`;
}
