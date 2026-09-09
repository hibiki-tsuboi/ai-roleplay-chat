import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class ChatSession {
    var draft = ""
    private(set) var pendingText: String?
    private(set) var errorMessage: String?

    let conversation: Conversation
    private let context: ModelContext
    private let api: ChatAPI

    init(conversation: Conversation, context: ModelContext, api: ChatAPI? = nil) {
        self.conversation = conversation
        self.context = context
        self.api = api ?? .configured
    }

    var isSending: Bool { pendingText != nil }
    var draftLength: Int { draft.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count }
    var canSend: Bool { !isSending && draftLength > 0 && draftLength <= ChatRequest.maxMessageLength }

    func send() async {
        guard canSend else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingText = text
        errorMessage = nil
        defer { pendingText = nil }

        do {
            let request = try ChatRequest(
                scenarioID: conversation.scenarioID,
                provider: conversation.provider,
                history: conversation.sortedMessages.map { APIMessage(role: $0.role, content: $0.content) },
                text: text
            )
            let reply = try await api.send(request)
            try Task.checkCancellation()
            conversation.appendTurn(userText: text, reply: reply.message.content)
            if conversation.provider == nil {
                conversation.providerID = reply.provider?.rawValue
            }
            do {
                try context.save()
            } catch {
                context.rollback()
                errorMessage = "会話を保存できませんでした。端末の空き容量などを確認して再送してください。"
                return
            }
            draft = ""
        } catch is CancellationError {
            // Keep the draft available when a request is cancelled.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
