//
//  LLMEvaluator.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/4/24.
//

import MLX
import MLXLLM
import MLXLMCommon
import MLXRandom
import Observation
import SwiftUI

enum LLMEvaluatorError: Error {
    case modelNotFound(String)
}

enum LLMProvider {
    case local(ModelConfiguration)
    case api(APIConfiguration)
}

extension LLMProvider: Hashable {
    static func == (lhs: LLMProvider, rhs: LLMProvider) -> Bool {
        switch (lhs, rhs) {
        case let (.local(lhsModel), .local(rhsModel)):
            return lhsModel.name == rhsModel.name
        case let (.api(lhsConfig), .api(rhsConfig)):
            return lhsConfig.name == rhsConfig.name
        default:
            return false
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case let .local(model):
            hasher.combine("local")
            hasher.combine(model.name)
        case let .api(config):
            hasher.combine("api")
            hasher.combine(config.name)
        }
    }
}

@Observable
class LLMEvaluator {
    // State
    var running = false
    var cancelled = false
    var output = ""
    var modelInfo = ""
    var stat = ""
    var progress = 0.0
    var thinkingTime: TimeInterval?
    var collapsed: Bool = false
    var isThinking: Bool = false
    var serverModels: [String] = []
    var selectedServerModel: String?
    var startTime: Date?
    var isLoadingModels = false
    var reasoningSteps: [String] = []

    var elapsedTime: TimeInterval? {
        if let startTime {
            return Date().timeIntervalSince(startTime)
        }
        return nil
    }

    var modelConfiguration = ModelConfiguration.defaultModel
    var currentProvider: LLMProvider = .local(ModelConfiguration.defaultModel)
    private var apiClient: APIClient?
    private weak var appManager: AppManager?

    enum LoadState {
        case idle
        case loaded(ModelContainer)
    }

    /// parameters controlling the output
    let generateParameters = GenerateParameters(temperature: 0.5)
    let maxTokens = 4096
    /// update the display every N tokens -- 4 looks like it updates continuously
    /// and is low overhead. observed ~15% reduction in tokens/s when updating on every token
    let displayEveryNTokens = 4

    var loadState = LoadState.idle

    init(appManager: AppManager) {
        self.appManager = appManager

        if appManager.preferredProvider == .api, let config = appManager.currentAPIConfiguration {
            currentProvider = .api(config)
            apiClient = APIClient(configuration: config)
        }

        // Restore cached models for the selected server
        if let server = appManager.currentServer {
            serverModels = appManager.getCachedModels(for: server.id)
            Task {
                let models = await fetchServerModels(for: server)
                if !models.isEmpty {
                    await MainActor.run {
                        self.serverModels = models
                        appManager.updateCachedModels(serverId: server.id, models: models)
                    }
                }
            }
        }
    }

    func switchModel(_ model: ModelConfiguration) async {
        currentProvider = .local(model)
        progress = 0.0
        loadState = .idle
        modelConfiguration = model
        _ = try? await load(modelName: model.name)
    }

    func switchToAPI(_ config: APIConfiguration) async {
        currentProvider = .api(config)
        apiClient = APIClient(configuration: config)
        progress = 0.0
        loadState = .idle
        appManager?.preferredProvider = .api
    }

    /// load and return the model -- can be called multiple times, subsequent calls will just return the loaded model
    func load(modelName: String) async throws -> ModelContainer {
        guard let model = ModelConfiguration.getModelByName(modelName) else {
            throw LLMEvaluatorError.modelNotFound(modelName)
        }

        switch loadState {
        case .idle:
            // limit the buffer cache
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

            let modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: model) { [modelConfiguration] progress in
                Task { @MainActor in
                    self.modelInfo = "Downloading \(modelConfiguration.name): \(Int(progress.fractionCompleted * 100))%"
                    self.progress = progress.fractionCompleted
                }
            }
            modelInfo = "Loaded \(modelConfiguration.id).  Weights: \(MLX.GPU.activeMemory / 1024 / 1024)M"
            loadState = .loaded(modelContainer)
            return modelContainer

        case let .loaded(modelContainer):
            return modelContainer
        }
    }

    func stop() {
        isThinking = false
        cancelled = true
    }

    @MainActor
    func generate(modelName: String, thread: Thread, systemPrompt: String = "") async -> String {
        guard !running else { return "" }

        running = true
        cancelled = false
        output = ""
        startTime = Date()
        reasoningSteps.removeAll()

        var finalOutput = ""
        defer {
            running = false
            isThinking = false
            startTime = nil
        }

        if appManager?.isUsingServer == true {
            finalOutput = await generateWithServer(thread: thread, systemPrompt: systemPrompt)
        } else {
            switch currentProvider {
            case .local(let model):
                finalOutput = await generateLocal(model: model, thread: thread, systemPrompt: systemPrompt)
            case .api:
                finalOutput = await generateAPI(thread: thread, systemPrompt: systemPrompt)
            }
        }

        return finalOutput
    }

    private func generateLocal(model: ModelConfiguration, thread: Thread, systemPrompt: String) async -> String {
        do {
            let modelContainer = try await load(modelName: model.name)

            let promptHistory = await modelContainer.configuration.getPromptHistory(thread: thread, systemPrompt: systemPrompt)

            if await modelContainer.configuration.modelType == .reasoning {
                isThinking = true
            }

            MLXRandom.seed(UInt64(Date.timeIntervalSinceReferenceDate * 1000))

            let result = try await modelContainer.perform { context in
                let input = try await context.processor.prepare(input: .init(messages: promptHistory))
                return try MLXLMCommon.generate(
                    input: input, parameters: generateParameters, context: context
                ) { tokens in

                    var cancelled = false
                    Task { @MainActor in
                        cancelled = self.cancelled
                    }

                    if tokens.count % displayEveryNTokens == 0 {
                        let text = context.tokenizer.decode(tokens: tokens)
                        Task { @MainActor in
                            self.output = text
                        }
                    }

                    if tokens.count >= maxTokens || cancelled {
                        return .stop
                    } else {
                        return .more
                    }
                }
            }

            if result.output != output {
                output = result.output
            }
            stat = " Tokens/second: \(String(format: "%.3f", result.tokensPerSecond))"

        } catch {
            output = "Failed: \(error)"
        }

        running = false
        return output
    }

    private func generateAPI(thread: Thread, systemPrompt: String) async -> String {
        guard let apiClient = apiClient else { return "API client not configured" }

        do {
            let promptHistory = buildFullHistory(thread: thread, systemPrompt: systemPrompt)
            let roles = promptHistory.compactMap { $0["role"] }.joined(separator: ",")
            print("LLM API request: \(promptHistory.count) messages | roles=\(roles)")
            let stream = try await apiClient.generateResponse(messages: promptHistory)

            for try await chunk in stream {
                if cancelled { break }
                output += chunk
            }

            stat = "API response completed"
        } catch {
            output = "API Error: \(error)"
        }

        running = false
        return output
    }

    private func generateWithServer(thread: Thread, systemPrompt: String) async -> String {
        guard let appManager = appManager,
              let server = appManager.currentServer,
              let modelName = appManager.currentModelName ?? selectedServerModel else {
            return "Error: Server configuration not available"
        }

        if modelName.hasPrefix("dall-e") {
            do {
                guard let lastMessage = thread.messages.last else {
                    return "No prompt provided"
                }
                return try await generateImage(prompt: lastMessage.content)
            } catch {
                return "Image generation failed: \(error.localizedDescription)"
            }
        }

        guard let chatURL = safeServerURL(base: server.url, path: "chat/completions") else {
            return "Error: Invalid server URL"
        }

        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !server.apiKey.isEmpty {
            request.setValue("Bearer \(server.apiKey)", forHTTPHeaderField: "Authorization")
        }

        var allMessages = buildFullHistory(thread: thread, systemPrompt: systemPrompt)
        let roles = allMessages.compactMap { $0["role"] }.joined(separator: ",")
        print("LLM server request: \(allMessages.count) messages | roles=\(roles)")
        var body: [String: Any] = [
            "stream": true,
            "model": modelName,
            "temperature": 1
        ]

        switch server.type {
        case .openai:
            if modelName.hasPrefix("o") {
                if !allMessages.isEmpty {
                    allMessages[0]["role"] = "user"
                } else {
                    allMessages.insert(["role": "user", "content": systemPrompt], at: 0)
                }
            }
            if modelName.hasPrefix("o1-") {
                body["max_completion_tokens"] = 2000
            } else {
                body["max_tokens"] = 2000
            }
        default:
            body["max_tokens"] = 2000
            body["ttl"] = 600
        }

        body["messages"] = allMessages

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: body)
            request.httpBody = jsonData

            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            var fullResponse = ""
            reasoningSteps.removeAll()

            for try await line in bytes.lines {
                guard !line.isEmpty else { continue }
                guard line.hasPrefix("data: ") else { continue }
                if line == "data: [DONE]" { break }

                let jsonString = String(line.dropFirst(6))
                guard let jsonData = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                    continue
                }

                if server.type == .openai {
                    if let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let delta = firstChoice["delta"] as? [String: Any] {

                        if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                            for toolCall in toolCalls {
                                if let function = toolCall["function"] as? [String: Any],
                                   let name = function["name"] as? String,
                                   let arguments = function["arguments"] as? String {
                                    reasoningSteps.append("🤔 \(name): \(arguments)")
                                    await updateOutput(fullResponse + "\n\n" + reasoningSteps.joined(separator: "\n"))
                                }
                            }
                        }

                        if let content = delta["content"] as? String {
                            fullResponse += content
                            await updateOutput(fullResponse + (reasoningSteps.isEmpty ? "" : "\n\n" + reasoningSteps.joined(separator: "\n")))
                        }
                    }
                } else if let choices = json["choices"] as? [[String: Any]],
                          let delta = choices.first?["delta"] as? [String: Any],
                          let content = delta["content"] as? String {
                    fullResponse += content
                    await updateOutput(fullResponse)
                }
            }

            return fullResponse
        } catch {
            await updateOutput("Error: \(error.localizedDescription)")
            return output
        }
    }

    @MainActor
    func fetchServerModels(for server: ServerConfig) async -> [String] {
        guard let url = safeServerURL(base: server.url, path: "models") else { return [] }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if !server.apiKey.isEmpty {
            request.setValue("Bearer \(server.apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["data"] as? [[String: Any]] {
                return models.compactMap { $0["id"] as? String }
            }
        } catch {
            print("❌ Error fetching models: \(error.localizedDescription)")
        }
        return []
    }

    @MainActor
    private func updateOutput(_ newOutput: String) {
        output = newOutput
    }

    // MARK: - Message history helpers

    private func buildFullHistory(thread: Thread, systemPrompt: String) -> [[String: String]] {
        var history: [[String: String]] = []
        history.append([
            "role": "system",
            "content": systemPrompt,
        ])

        for message in thread.sortedMessages {
            history.append([
                "role": message.role.rawValue,
                "content": message.content,
            ])
        }

        return history
    }

    // MARK: - Image generation

    @MainActor
    func generateImage(prompt: String) async throws -> String {
        guard let appManager = appManager,
              let serverConfig = appManager.currentServer,
              let modelName = appManager.currentModelName else {
            throw NSError(domain: "LLMEvaluator", code: -1, userInfo: [NSLocalizedDescriptionKey: "No server configured"])
        }

        guard let url = safeServerURL(base: serverConfig.url, path: "images/generations") else {
            throw NSError(domain: "LLMEvaluator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        let body: [String: Any] = [
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024",
            "quality": "standard",
            "response_format": "url",
            "model": modelName
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(serverConfig.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let error = json?["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
        }

        guard let dataArray = json?["data"] as? [[String: Any]],
              let firstImage = dataArray.first,
              let imageUrl = firstImage["url"] as? String else {
            throw NSError(domain: "OpenAI", code: -1, userInfo: [NSLocalizedDescriptionKey: "No image URL in response"])
        }

        return "![Generated Image](\(imageUrl))"
    }

    // MARK: - Helpers

    private func safeServerURL(base: String, path: String) -> URL? {
        var cleaned = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleaned.lowercased().hasPrefix("http") {
            cleaned = "https://" + cleaned
        }
        if cleaned.lowercased().hasPrefix("http://") && !cleaned.contains("localhost") && !cleaned.contains("127.0.0.1") {
            cleaned = cleaned.replacingOccurrences(of: "http://", with: "https://")
        }
        return URL(string: cleaned)?.appendingPathComponent(path)
    }
}

private extension String {
    func stripPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
