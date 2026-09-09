import Foundation

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case openai
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .gemini: "Gemini"
        }
    }
}
