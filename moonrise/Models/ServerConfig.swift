import Foundation

struct ServerConfig: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var url: String
    var apiKey: String
    var type: ServerType

    init(id: UUID = UUID(), name: String = "", url: String, apiKey: String = "", type: ServerType = .custom) {
        self.id = id
        self.name = name
        self.url = url
        self.apiKey = apiKey
        self.type = type
    }

    func sanitized() -> ServerConfig {
        var cleanedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedURL.lowercased().hasPrefix("http") {
            cleanedURL = "https://" + cleanedURL
        }
        // Prefer https unless explicitly local
        if cleanedURL.lowercased().hasPrefix("http://") && !cleanedURL.contains("localhost") && !cleanedURL.contains("127.0.0.1") {
            cleanedURL = cleanedURL.replacingOccurrences(of: "http://", with: "https://")
        }
        return ServerConfig(id: id, name: name.isEmpty ? type.rawValue : name, url: cleanedURL, apiKey: apiKey, type: type)
    }

    enum ServerType: String, Codable, CaseIterable {
        case openai = "OpenAI"
        case ollama = "Ollama"
        case lmStudio = "LM Studio"
        case custom = "Custom"

        var defaultURL: String {
            switch self {
            case .openai: return "https://api.openai.com/v1"
            case .ollama: return "http://localhost:11434/v1"
            case .lmStudio: return "http://localhost:1234/v1"
            case .custom: return "http"
            }
        }
    }
}
