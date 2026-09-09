// Local HTTP fixture for AIRoleplayChatUITests. Never calls a real AI service.
import { createServer } from "node:http";

let failNextRetry = true;
let failNextEvaluationRetry = true;
const evaluation = {
  totalScore: 78,
  criteria: {
    listening: { score: 20, reason: "責める前に、遅れている理由を確認できました。" },
    consideration: { score: 21, reason: "困りごとを話しやすい言葉で応じられました。" },
    clarity: { score: 19, reason: "次に進める作業を伝えられました。" },
    action: { score: 18, reason: "次の報告時刻も確認すると、さらに良くなります。" },
  },
  goodPoint: "事情を聞いてから、一緒に解決しようとする姿勢を示せました。",
  improvement: "最後に次の報告時刻を決めると、お互いに進捗を確認しやすくなります。",
  rephrase: "では、今日15時に進み具合を教えてもらえる？ 困っていることがあれば、その前でも相談してね。",
};
createServer(async (request, response) => {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  response.setHeader("Content-Type", "application/json; charset=utf-8");
  if (request.method !== "POST" || !["/v1/chat", "/v1/evaluation"].includes(request.url)) {
    response.writeHead(404).end(JSON.stringify({ error: { code: "not_found", message: "Not found" } }));
    return;
  }
  try {
    const { scenarioId, messages, provider = "gemini", practice } = JSON.parse(Buffer.concat(chunks).toString());
    if (scenarioId !== "late-report") throw new Error("Invalid request");
    if (provider !== "openai" && provider !== "gemini") throw new Error("Invalid provider");
    if (request.url === "/v1/evaluation") {
      if (practice !== "five-turns" || messages.length !== 10 || messages.at(-1)?.role !== "assistant") throw new Error("Incomplete practice");
      if (messages[0]?.content === "evaluation-retry-once") {
        const fail = failNextEvaluationRetry;
        failNextEvaluationRetry = !failNextEvaluationRetry;
        if (fail) {
          response.writeHead(503).end(JSON.stringify({ error: { code: "unavailable", message: "結果を取得できませんでした。もう一度お試しください。" } }));
          return;
        }
      }
      response.end(JSON.stringify({ provider, evaluation }));
      return;
    }
    if (messages.at(-1)?.role !== "user") throw new Error("Invalid request");
    if (practice === "five-turns" && messages.length > 9) throw new Error("Practice complete");
    if (messages.at(-1).content === "retry-once") {
      const fail = failNextRetry;
      failNextRetry = !failNextRetry;
      if (fail) {
        response.writeHead(503).end(JSON.stringify({ error: { code: "unavailable", message: "少し待ってから再送してください。" } }));
        return;
      }
    }
    const content = practice === "five-turns" && messages.length === 9
      ? "承知しました。進み具合を整理して、改めて報告します。ありがとうございました。"
      : messages.length > 1
      ? "共有して一緒に確認していただけると助かります。"
      : "集計に時間がかかっています。";
    response.end(JSON.stringify({ provider, practice, message: { role: "assistant", content: `${provider === "openai" ? "OpenAI" : "Gemini"}: ${content}` } }));
  } catch {
    response.writeHead(400).end(JSON.stringify({ error: { code: "invalid_request", message: "Invalid request" } }));
  }
}).listen(8788, "127.0.0.1", () => {
  console.log("UI test mock listening on http://localhost:8788 (no real AI calls)");
});
