import SwiftUI

struct APISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var baseURL = "https://api.openai.com/v1"
    @State private var modelName = "gpt-4o-mini"
    @State private var customName = "OpenAI"
    @State private var selectedPreset: APIConfiguration?
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("API Configuration")) {
                    TextField("Name", text: $customName)
                    TextField("Base URL", text: $baseURL)
                    TextField("Model Name", text: $modelName)
                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)
                }
                
                Section(header: Text("Presets")) {
                    Button("OpenAI") {
                        selectedPreset = .openAI
                        applyPreset(.openAI)
                    }
                    .foregroundColor(.blue)
                    
                    Button("Anthropic") {
                        selectedPreset = .anthropic
                        applyPreset(.anthropic)
                    }
                    .foregroundColor(.blue)
                    
                    Button("Ollama (Local)") {
                        selectedPreset = .ollama
                        applyPreset(.ollama)
                    }
                    .foregroundColor(.green)
                }
                
                Section(header: Text("Current Configuration")) {
                    HStack {
                        Text("Name:")
                        Spacer()
                        Text(customName)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Base URL:")
                        Spacer()
                        Text(baseURL)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    HStack {
                        Text("Model:")
                        Spacer()
                        Text(modelName)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("API Key:")
                        Spacer()
                        Text(apiKey.isEmpty ? "Not set" : "••••••••")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("API Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveConfiguration()
                    }
                    .disabled(customName.isEmpty || baseURL.isEmpty || modelName.isEmpty)
                }
            }
        }
    }
    
    private func applyPreset(_ preset: APIConfiguration) {
        customName = preset.name
        baseURL = preset.baseURL
        modelName = preset.modelName
        apiKey = preset.apiKey
    }
    
    private func saveConfiguration() {
        // Here you would save the configuration to UserDefaults or your app's storage
        // For now, we'll just dismiss the view
        dismiss()
    }
}

#Preview {
    APISettingsView()
}
