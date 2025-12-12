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
@MainActor
class LLMEvaluator {
    var running = false
    var cancelled = false
    var output = ""
    var modelInfo = ""
    var stat = ""
    var progress = 0.0
    var thinkingTime: TimeInterval?
    var collapsed: Bool = false
    var isThinking: Bool = false

    var elapsedTime: TimeInterval? {
        if let startTime {
            return Date().timeIntervalSince(startTime)
        }

        return nil
    }

    private var startTime: Date?

    var modelConfiguration = ModelConfiguration.defaultModel
    
    var currentProvider: LLMProvider = .local(ModelConfiguration.defaultModel)
    private var apiClient: APIClient?

    func switchModel(_ model: ModelConfiguration) async {
        currentProvider = .local(model)
        progress = 0.0 // reset progress
        loadState = .idle
        modelConfiguration = model
        _ = try? await load(modelName: model.name)
    }
    
    func switchToAPI(_ config: APIConfiguration) async {
        currentProvider = .api(config)
        apiClient = APIClient(configuration: config)
        progress = 0.0
        loadState = .idle
    }

    /// parameters controlling the output
    let generateParameters = GenerateParameters(temperature: 0.5)
    let maxTokens = 4096

    /// update the display every N tokens -- 4 looks like it updates continuously
    /// and is low overhead.  observed ~15% reduction in tokens/s when updating
    /// on every token
    let displayEveryNTokens = 4

    enum LoadState {
        case idle
        case loaded(ModelContainer)
    }

    var loadState = LoadState.idle

    /// load and return the model -- can be called multiple times, subsequent calls will
    /// just return the loaded model
    func load(modelName: String) async throws -> ModelContainer {
        guard let model = ModelConfiguration.getModelByName(modelName) else {
            throw LLMEvaluatorError.modelNotFound(modelName)
        }

        switch loadState {
        case .idle:
            // limit the buffer cache
            MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)

            let modelContainer = try await LLMModelFactory.shared.loadContainer(configuration: model) {
                [modelConfiguration] progress in
                Task { @MainActor in
                    self.modelInfo =
                        "Downloading \(modelConfiguration.name): \(Int(progress.fractionCompleted * 100))%"
                    self.progress = progress.fractionCompleted
                }
            }
            modelInfo =
                "Loaded \(modelConfiguration.id).  Weights: \(MLX.GPU.activeMemory / 1024 / 1024)M"
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

    func generate(modelName: String, thread: Thread, systemPrompt: String) async -> String {
        guard !running else { return "" }

        running = true
        cancelled = false
        output = ""
        startTime = Date()

        switch currentProvider {
        case .local(let model):
            return await generateLocal(model: model, thread: thread, systemPrompt: systemPrompt)
        case .api:
            return await generateAPI(thread: thread, systemPrompt: systemPrompt)
        }
    }
    
    private func generateLocal(model: ModelConfiguration, thread: Thread, systemPrompt: String) async -> String {
        do {
            let modelContainer = try await load(modelName: model.name)

            // augment the prompt as needed
            let promptHistory = await modelContainer.configuration.getPromptHistory(thread: thread, systemPrompt: systemPrompt)

            if await modelContainer.configuration.modelType == .reasoning {
                isThinking = true
            }

            // each time you generate you will get something new
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

                    // update the output -- this will make the view show the text as it generates
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

            // update the text if needed, e.g. we haven't displayed because of displayEveryNTokens
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
            let promptHistory = modelConfiguration.getPromptHistory(thread: thread, systemPrompt: systemPrompt)
            
            let stream = try await apiClient.generateResponse(messages: promptHistory, systemPrompt: systemPrompt)
            
            for try await chunk in stream {
                if cancelled {
                    break
                }
                output += chunk
            }
            
            stat = "API response completed"
        } catch {
            output = "API Error: \(error)"
        }
        
        running = false
        return output
    }
}
