import Foundation
import SwiftData

@Model
final class Conversation {
    var id: UUID
    var scenarioID: String
    var title: String
    var characterName: String
    var createdAt: Date
    var updatedAt: Date
    // Older conversations have no recorded provider; retain that distinction when migrating.
    var providerID: String? = nil
    // Nil preserves free-form conversations created before five-turn practice.
    var practiceVersion: Int? = nil
    var evaluationData: Data? = nil
    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage] = []

    init(scenario: Scenario = .lateReport, provider: AIProvider? = nil) {
        id = UUID()
        scenarioID = scenario.id
        title = scenario.title
        characterName = scenario.characterName
        providerID = provider?.rawValue
        practiceVersion = 1
        let now = Date()
        createdAt = now
        updatedAt = now
    }

    var sortedMessages: [ChatMessage] {
        messages.sorted { $0.position < $1.position }
    }

    var provider: AIProvider? {
        providerID.flatMap(AIProvider.init(rawValue:))
    }

    static let turnLimit = 5
    var isPractice: Bool { practiceVersion == 1 }
    var completedTurns: Int { messages.filter { $0.role == .assistant }.count }
    var isComplete: Bool { isPractice && completedTurns >= Self.turnLimit }
    var evaluation: PracticeEvaluation? {
        guard let evaluationData,
              let value = try? JSONDecoder().decode(PracticeEvaluation.self, from: evaluationData),
              value.isValid else { return nil }
        return value
    }

    func appendTurn(userText: String, reply: String) {
        let position = (messages.map(\.position).max() ?? -1) + 1
        messages.append(ChatMessage(role: .user, content: userText, position: position))
        messages.append(ChatMessage(role: .assistant, content: reply, position: position + 1))
        updatedAt = Date()
    }
}

@Model
final class ChatMessage {
    var id: UUID
    var role: MessageRole
    var content: String
    var position: Int
    var conversation: Conversation?

    init(role: MessageRole, content: String, position: Int) {
        id = UUID()
        self.role = role
        self.content = content
        self.position = position
    }
}
