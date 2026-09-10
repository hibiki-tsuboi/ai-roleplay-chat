import Foundation
import Testing
@testable import AIRoleplayChat

@MainActor
struct ScenarioTests {
    @Test func everyScenarioIsDistinctAndComplete() {
        #expect(Scenario.all.count > 1)
        #expect(Set(Scenario.all.map(\.id)).count == Scenario.all.count)
        #expect(Set(Scenario.all.map(\.characterName)).count == Scenario.all.count)
        for scenario in Scenario.all {
            #expect(Scenario.named(scenario.id)?.id == scenario.id)
            #expect(scenario.summary.contains(scenario.characterName))
            #expect(!scenario.title.isEmpty)
            #expect(!scenario.opener.isEmpty)
        }
        #expect(Scenario.all.contains { $0.id == Scenario.lateReport.id })
        #expect(Scenario.named("unknown") == nil)
    }

    // The persona lives on the server; only the id travels, so a conversation has to carry its own labels.
    @Test func conversationKeepsTheScenarioItStartedWith() throws {
        for scenario in Scenario.all {
            let conversation = Conversation(scenario: scenario, provider: .gemini)
            #expect(conversation.scenarioID == scenario.id)
            #expect(conversation.title == scenario.title)
            #expect(conversation.characterName == scenario.characterName)
            #expect(conversation.isPractice)

            let request = try ChatRequest(scenarioID: conversation.scenarioID, provider: conversation.provider,
                                          history: [], text: "状況を聞かせてもらえる？", isPractice: true)
            #expect(request.scenarioId == scenario.id)
        }
    }
}
