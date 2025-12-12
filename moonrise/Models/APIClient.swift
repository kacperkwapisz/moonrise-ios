import Foundation

actor APIClient {
    private let configuration: APIConfiguration
    
    init(configuration: APIConfiguration) {
        self.configuration = configuration
    }
    
    func generateResponse(messages: [[String: String]], systemPrompt: String) async throws -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try createRequest(messages: messages, systemPrompt: systemPrompt)
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200 else {
                        throw APIError.invalidResponse
                    }
                    
                    try await processStreamResponse(data: data, continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func createRequest(messages: [[String: String]], systemPrompt: String) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "\(configuration.baseURL)/chat/completions")!)
        request.httpMethod = "POST"
        
        // Only add Authorization header if API key is provided
        if !configuration.apiKey.isEmpty {
            request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ChatCompletionRequest(
            model: configuration.modelName,
            messages: [["role": "system", "content": systemPrompt]] + messages,
            stream: true,
            temperature: 0.5,
            max_tokens: 4096
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }
    
    private func processStreamResponse(data: Data, continuation: AsyncThrowingStream<String, Error>.Continuation) async throws {
        let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []
        
        for line in lines {
            guard line.hasPrefix("data: "),
                  let jsonData = line.dropFirst(6).data(using: .utf8),
                  !jsonData.isEmpty else { continue }
            
            if line.contains("[DONE]") {
                continuation.finish()
                return
            }
            
            let response = try JSONDecoder().decode(StreamResponse.self, from: jsonData)
            if let content = response.choices.first?.delta.content {
                continuation.yield(content)
            }
        }
        continuation.finish()
    }
}

// API Models
struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [[String: String]]
    let stream: Bool
    let temperature: Double
    let max_tokens: Int
}

struct StreamResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let delta: Delta
}

struct Delta: Codable {
    let content: String?
}

enum APIError: Error, LocalizedError {
    case invalidResponse
    case invalidAPIKey
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from API"
        case .invalidAPIKey:
            return "Invalid API key"
        case .networkError:
            return "Network error occurred"
        }
    }
}
