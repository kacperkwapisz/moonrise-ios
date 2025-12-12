import Foundation

struct APIConfiguration: Codable, Identifiable, Equatable {
    let id = UUID()
    let name: String
    let baseURL: String
    let apiKey: String
    let modelName: String
    let isDefault: Bool
    
    init(name: String, baseURL: String, apiKey: String, modelName: String, isDefault: Bool = false) {
        self.name = name
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.modelName = modelName
        self.isDefault = isDefault
    }
}

extension APIConfiguration {
    static let openAI = APIConfiguration(
        name: "OpenAI",
        baseURL: "https://api.openai.com/v1",
        apiKey: "",
        modelName: "gpt-4o-mini",
        isDefault: true
    )
    
    static let anthropic = APIConfiguration(
        name: "Anthropic",
        baseURL: "https://api.anthropic.com/v1",
        apiKey: "",
        modelName: "claude-3-haiku-20240307"
    )
    
    static let ollama = APIConfiguration(
        name: "Ollama",
        baseURL: "http://localhost:11434",
        apiKey: "",
        modelName: "llama3.2:1b"
    )
}
