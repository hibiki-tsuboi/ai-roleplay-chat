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
    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage] = []

    init(scenario: Scenario = .lateReport) {
        id = UUID()
        scenarioID = scenario.id
        title = scenario.title
        characterName = scenario.characterName
        let now = Date()
        createdAt = now
        updatedAt = now
    }

    var sortedMessages: [ChatMessage] {
        messages.sorted { $0.position < $1.position }
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
