import Foundation

struct PracticeEvaluation: Codable, Equatable {
    struct Assessment: Codable, Equatable {
        let score: Int
        let reason: String

        var isValid: Bool { (0...25).contains(score) && PracticeEvaluation.validText(reason, limit: 300) }
    }

    struct Criteria: Codable, Equatable {
        let listening: Assessment
        let consideration: Assessment
        let clarity: Assessment
        let action: Assessment

        var rows: [(title: String, assessment: Assessment)] {
            [("事情を聞く", listening), ("相手への配慮", consideration),
             ("指示の明確さ", clarity), ("次の行動の合意", action)]
        }
    }

    let totalScore: Int
    let criteria: Criteria
    let goodPoint: String
    let improvement: String
    let rephrase: String

    var isValid: Bool {
        criteria.rows.allSatisfy { $0.assessment.isValid }
            && totalScore == criteria.rows.reduce(0) { $0 + $1.assessment.score }
            && [goodPoint, improvement, rephrase].allSatisfy { Self.validText($0, limit: 500) }
    }

    private static func validText(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= limit
    }
}

struct EvaluationRequest: Encodable {
    let scenarioId: String
    let provider: AIProvider
    let practice = ChatRequest.practiceMode
    let messages: [APIMessage]

    init(conversation: Conversation) throws {
        guard conversation.isComplete, let provider = conversation.provider else { throw ChatAPIError.invalidMessage }
        scenarioId = conversation.scenarioID
        self.provider = provider
        messages = conversation.sortedMessages.map { APIMessage(role: $0.role, content: $0.content) }
        guard messages.count == Conversation.turnLimit * 2,
              messages.enumerated().allSatisfy({ index, message in
                  message.role == (index % 2 == 0 ? .user : .assistant)
                      && !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && message.content.utf16.count <= ChatRequest.maxMessageLength
              }) else { throw ChatAPIError.invalidMessage }
    }
}

struct EvaluationResponse: Decodable {
    let provider: AIProvider
    let evaluation: PracticeEvaluation
}
