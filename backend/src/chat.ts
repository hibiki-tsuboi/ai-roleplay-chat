export const scenarioID = "late-report";
export const maxMessages = 40;
export const maxMessageLength = 4_000;
export const maxTotalLength = 24_000;

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

export interface ChatRequest {
  scenarioId: typeof scenarioID;
  messages: ChatMessage[];
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
  if (!isRecord(value) || value.scenarioId !== scenarioID || !Array.isArray(value.messages)) {
    return null;
  }
  if (value.messages.length < 1 || value.messages.length > maxMessages) return null;

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
    messages.push({ role: message.role, content: message.content });
  }
  if (totalLength > maxTotalLength || messages.at(-1)?.role !== "user") return null;
  return { scenarioId: scenarioID, messages };
}
