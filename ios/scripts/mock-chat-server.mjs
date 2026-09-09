// Local HTTP fixture for AIRoleplayChatUITests. Never calls OpenAI.
import { createServer } from "node:http";

let failNextRetry = true;
createServer(async (request, response) => {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  response.setHeader("Content-Type", "application/json; charset=utf-8");
  if (request.method !== "POST" || request.url !== "/v1/chat") {
    response.writeHead(404).end(JSON.stringify({ error: { code: "not_found", message: "Not found" } }));
    return;
  }
  try {
    const { scenarioId, messages } = JSON.parse(Buffer.concat(chunks).toString());
    if (scenarioId !== "late-report" || messages.at(-1)?.role !== "user") throw new Error("Invalid request");
    if (messages.at(-1).content === "retry-once") {
      const fail = failNextRetry;
      failNextRetry = !failNextRetry;
      if (fail) {
        response.writeHead(503).end(JSON.stringify({ error: { code: "unavailable", message: "少し待ってから再送してください。" } }));
        return;
      }
    }
    const content = messages.length > 1
      ? "共有して一緒に確認していただけると助かります。"
      : "集計に時間がかかっています。";
    response.end(JSON.stringify({ message: { role: "assistant", content } }));
  } catch {
    response.writeHead(400).end(JSON.stringify({ error: { code: "invalid_request", message: "Invalid request" } }));
  }
}).listen(8788, "127.0.0.1", () => {
  console.log("UI test mock listening on http://localhost:8788 (no OpenAI calls)");
});
