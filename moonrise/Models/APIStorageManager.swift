import Foundation

@Observable
class APIStorageManager {
    static let shared = APIStorageManager()
    
    private let userDefaults = UserDefaults.standard
    private let apiConfigurationsKey = "api_configurations"
    private let currentAPIConfigKey = "current_api_config"
    
    var apiConfigurations: [APIConfiguration] = []
    var currentAPIConfig: APIConfiguration?
    
    private init() {
        loadConfigurations()
    }
    
    func addConfiguration(_ config: APIConfiguration) {
        apiConfigurations.append(config)
        saveConfigurations()
    }
    
    func updateConfiguration(_ config: APIConfiguration) {
        if let index = apiConfigurations.firstIndex(where: { $0.id == config.id }) {
            apiConfigurations[index] = config
            saveConfigurations()
        }
    }
    
    func removeConfiguration(_ config: APIConfiguration) {
        apiConfigurations.removeAll { $0.id == config.id }
        if currentAPIConfig?.id == config.id {
            currentAPIConfig = nil
        }
        saveConfigurations()
    }
    
    func setCurrentConfiguration(_ config: APIConfiguration?) {
        currentAPIConfig = config
        userDefaults.set(currentAPIConfig?.id.uuidString, forKey: currentAPIConfigKey)
    }
    
    private func loadConfigurations() {
        if let data = userDefaults.data(forKey: apiConfigurationsKey),
           let configs = try? JSONDecoder().decode([APIConfiguration].self, from: data) {
            apiConfigurations = configs
        } else {
            // Add default configurations
            apiConfigurations = [.openAI, .anthropic, .ollama]
        }
        
        if let currentIDString = userDefaults.string(forKey: currentAPIConfigKey),
           let currentID = UUID(uuidString: currentIDString),
           let config = apiConfigurations.first(where: { $0.id == currentID }) {
            currentAPIConfig = config
        }
    }
    
    private func saveConfigurations() {
        if let data = try? JSONEncoder().encode(apiConfigurations) {
            userDefaults.set(data, forKey: apiConfigurationsKey)
        }
    }
}
