import Foundation

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct APIMessage: Codable, Equatable {
    let role: MessageRole
    let content: String
}

struct ChatRequest: Encodable {
    let scenarioId: String
    let messages: [APIMessage]

    // Match backend/src/chat.ts and docs/api.md. Swift's Character count differs from UTF-16.
    static let maxMessages = 40
    static let maxMessageLength = 4_000
    static let maxTotalLength = 24_000

    init(scenarioID: String, history: [APIMessage], text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf16.count <= Self.maxMessageLength else {
            throw ChatAPIError.invalidMessage
        }
        scenarioId = scenarioID
        var recent = Array((history + [APIMessage(role: .user, content: text)]).suffix(Self.maxMessages))
        while recent.count > 1 && recent.reduce(0, { $0 + $1.content.utf16.count }) > Self.maxTotalLength {
            recent.removeFirst()
        }
        messages = recent
    }
}

struct ChatResponse: Decodable {
    let message: APIMessage
}

private struct APIErrorResponse: Decodable {
    struct Detail: Decodable {
        let code: String
        let message: String
    }
    let error: Detail
}

enum ChatAPIError: LocalizedError {
    case notConfigured
    case invalidMessage
    case invalidResponse
    case server(String)
    case connectionFailed
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "チャットサーバーの接続先が設定されていません。"
        case .invalidMessage:
            "空白以外のメッセージを4,000文字以内で入力してください。"
        case .invalidResponse:
            "返答を読み取れませんでした。もう一度送信してください。"
        case .server(let message):
            message
        case .connectionFailed:
            "サーバーに接続できません。接続を確認して、もう一度送信してください。"
        case .timedOut:
            "返答に時間がかかっています。少し待ってから、もう一度送信してください。"
        }
    }
}

struct ChatAPI {
    var baseURL: URL?
    var session: URLSession = .shared
    #if DEBUG
    var developmentAccessToken: String?
    #endif

    static var configured: ChatAPI {
        var address = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String ?? ""
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["ROLEPLAY_API_BASE_URL"] {
            address = override
        }
        #endif
        var api = ChatAPI(baseURL: URL(string: address))
        #if DEBUG
        api.developmentAccessToken = ProcessInfo.processInfo.environment["ROLEPLAY_DEV_ACCESS_TOKEN"]
        #endif
        return api
    }

    func send(_ payload: ChatRequest) async throws -> APIMessage {
        guard let baseURL, let host = baseURL.host, !host.isEmpty,
              baseURL.user == nil, baseURL.password == nil else {
            throw ChatAPIError.notConfigured
        }
        #if DEBUG
        guard baseURL.scheme == "https" || baseURL.scheme == "http" else {
            throw ChatAPIError.notConfigured
        }
        #else
        guard baseURL.scheme == "https" else { throw ChatAPIError.notConfigured }
        #endif

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        #if DEBUG
        if let token = developmentAccessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            guard baseURL.scheme == "https" else { throw ChatAPIError.notConfigured }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        #endif
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw error.code == .timedOut ? ChatAPIError.timedOut : ChatAPIError.connectionFailed
        }
        guard let response = response as? HTTPURLResponse else { throw ChatAPIError.invalidResponse }
        let decoder = JSONDecoder()
        guard (200..<300).contains(response.statusCode) else {
            let detail = try? decoder.decode(APIErrorResponse.self, from: data)
            throw ChatAPIError.server(detail?.error.message ?? "返答を取得できませんでした。もう一度送信してください。")
        }
        guard let reply = try? decoder.decode(ChatResponse.self, from: data),
              reply.message.role == .assistant,
              !reply.message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              reply.message.content.utf16.count <= ChatRequest.maxMessageLength else {
            throw ChatAPIError.invalidResponse
        }
        return reply.message
    }
}
