import Foundation
import SwiftData
import Testing
@testable import AIRoleplayChat

// Preserve the model shape from before per-conversation AI selection.
private enum LegacyChatStore {
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
}

@MainActor
struct StoreMigrationTests {
    @Test func existingHistoryMigratesWithoutGuessingItsProvider() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.store")
        do {
            let schema = Schema([LegacyChatStore.Conversation.self, LegacyChatStore.ChatMessage.self])
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let conversation = LegacyChatStore.Conversation()
            context.insert(conversation)
            conversation.appendTurn(userText: "進み具合は？", reply: "あと少しです。")
            try context.save()
        }
        let schema = Schema([Conversation.self, ChatMessage.self])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let conversation = try #require(context.fetch(FetchDescriptor<Conversation>()).first)
        #expect(conversation.providerID == nil)
        #expect(conversation.sortedMessages.map(\.content) == ["進み具合は？", "あと少しです。"])
        #expect(conversation.messages.allSatisfy { $0.conversation?.id == conversation.id })
        conversation.providerID = AIProvider.gemini.rawValue
        try context.save()
    }
}
