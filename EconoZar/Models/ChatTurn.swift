import Foundation
import SwiftData

struct ChatSuggestion: Codable, Equatable {
    var valor: Double
    var ativo: String
    var cofre: String
    var rendimentoCofre: String
    var estimativaAtivo: String
}

@Model
final class ChatTurn {
    var role: String
    var text: String
    var createdAt: Date
    var suggestionJSON: String
    var decision: String

    init(
        role: String,
        text: String,
        createdAt: Date = .now,
        suggestionJSON: String = "",
        decision: String = ""
    ) {
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.suggestionJSON = suggestionJSON
        self.decision = decision
    }

    var isUser: Bool { role == "user" }

    var suggestion: ChatSuggestion? {
        guard let data = suggestionJSON.data(using: .utf8), !suggestionJSON.isEmpty else { return nil }
        return try? JSONDecoder().decode(ChatSuggestion.self, from: data)
    }

    func store(_ suggestion: ChatSuggestion?) {
        guard let suggestion,
              let data = try? JSONEncoder().encode(suggestion),
              let json = String(data: data, encoding: .utf8) else {
            suggestionJSON = ""
            return
        }
        suggestionJSON = json
    }
}
