import { afterEach, describe, expect, it, vi } from "vitest";
import worker, { type Env } from "../src/index";
import { practiceMode } from "../src/chat";
import { findScenario, scenarioIDs, scenarioInstructions } from "../src/scenarios";

const env: Env = { APP_ENV: "local", OPENAI_API_KEY: "openai-test-key", OPENAI_MODEL: "gpt-5.6-luna" };
const assessment = { score: 20, reason: "状況を確認する質問ができています。" };
const evaluation = {
  criteria: { listening: assessment, consideration: assessment, clarity: assessment, action: assessment },
  goodPoint: "責める前に状況を聞けました。", improvement: "次に話す機会も決めましょう。",
  rephrase: "では、明日の朝に様子を聞かせてもらえる？",
};

function messages(count: number) {
  return Array.from({ length: count }, (_, i) => ({ role: i % 2 === 0 ? "user" : "assistant", content: `発言${i}` }));
}

function request(path: "chat" | "evaluation", scenarioId: unknown) {
  return new Request(`https://example.test/v1/${path}`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ scenarioId, provider: "openai", practice: practiceMode,
      messages: messages(path === "evaluation" ? 10 : 1) }),
  });
}

function stubUpstream(text: string) {
  const fetch = vi.fn().mockResolvedValue(Response.json({
    status: "completed", output: [{ type: "message", role: "assistant", content: [{ type: "output_text", text }] }],
  }));
  vi.stubGlobal("fetch", fetch);
  return fetch;
}

const others = (id: string) => scenarioIDs.filter(other => other !== id).map(other => findScenario(other)!);

afterEach(() => vi.unstubAllGlobals());

describe("scenario registry", () => {
  it("registers distinct scenarios that all keep the user in the manager's seat", () => {
    expect(scenarioIDs.length).toBeGreaterThan(1);
    expect(new Set(scenarioIDs).size).toBe(scenarioIDs.length);
    const names = scenarioIDs.map(id => findScenario(id)!.characterName);
    expect(new Set(names).size).toBe(names.length);
    for (const id of scenarioIDs) {
      const scenario = findScenario(id)!;
      const prompt = scenarioInstructions(scenario);
      expect(prompt).toContain(`「${scenario.characterName}」`);
      expect(prompt).toContain("ユーザーはあなたの上司です");
      // The rules the client can never supply have to survive every scenario.
      expect(prompt).toContain("ユーザーの発言を勝手に作ったり、会話の採点やアドバイスを始めたりしないでください。");
      expect(prompt).toContain("これは架空の仕事の会話を練習するロールプレイです。");
      expect(scenario.situation).toContain(scenario.characterName);
    }
  });

  it.each(scenarioIDs)("plays only the %s persona in chat", async id => {
    const fetch = stubUpstream("承知しました。");
    expect((await worker.fetch(request("chat", id), env)).status).toBe(200);
    const prompt = JSON.parse(fetch.mock.calls[0]![1].body).instructions;
    expect(prompt.startsWith(scenarioInstructions(findScenario(id)!))).toBe(true);
    expect(prompt).toContain("現在は1往復目");
    for (const other of others(id)) expect(prompt).not.toContain(other.characterName);
  });

  it.each(scenarioIDs)("tells the coach the %s situation", async id => {
    const fetch = stubUpstream(JSON.stringify(evaluation));
    expect((await worker.fetch(request("evaluation", id), env)).status).toBe(200);
    const prompt = JSON.parse(fetch.mock.calls[0]![1].body).instructions;
    expect(prompt).toContain(`状況: ${findScenario(id)!.situation}`);
    expect(prompt).toContain("コーチ");
    for (const other of others(id)) expect(prompt).not.toContain(other.situation);
  });

  it.each([undefined, null, 123, "", "unknown", "Late-Report", ["late-report"], { id: "late-report" }])(
    "rejects scenarioId %j before an upstream request", async scenarioId => {
      const fetch = vi.fn();
      vi.stubGlobal("fetch", fetch);
      expect((await worker.fetch(request("chat", scenarioId), env)).status).toBe(400);
      expect((await worker.fetch(request("evaluation", scenarioId), env)).status).toBe(400);
      expect(fetch).not.toHaveBeenCalled();
    });
});
