//
//  ModelsSettingsView.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/5/24.
//

import SwiftUI
import MLXLMCommon

struct ModelsSettingsView: View {
    @EnvironmentObject var appManager: AppManager
    @Environment(LLMEvaluator.self) var llm
    @State var showOnboardingInstallModelView = false
    @State var showAPISettings = false
    
    var body: some View {
        Form {
            Section(header: Text("Provider")) {
                Picker("Provider", selection: Binding(
                    get: { llm.currentProvider },
                    set: { newProvider in
                        Task {
                            switch newProvider {
                            case .local(let model):
                                appManager.preferredProvider = .local
                                appManager.currentModelName = model.name
                                await llm.switchModel(model)
                            case .api(let config):
                                appManager.setCurrentAPIConfiguration(config)
                                await llm.switchToAPI(config)
                            }
                        }
                    }
                )) {
                    Text("Local Models").tag(LLMProvider.local(ModelConfiguration.defaultModel))
                    Text("API").tag(LLMProvider.api(APIConfiguration.openAI))
                }
                .pickerStyle(.segmented)
            }
            
            if case .local = llm.currentProvider {
                Section(header: Text("installed")) {
                ForEach(appManager.installedModels, id: \.self) { modelName in
                    Button {
                        Task {
                            await switchModel(modelName)
                        }
                    } label: {
                        Label {
                            Text(appManager.modelDisplayName(modelName))
                                .tint(.primary)
                        } icon: {
                            Image(systemName: appManager.currentModelName == modelName ? "checkmark.circle.fill" : "circle")
                        }
                    }
                    #if os(macOS)
                    .buttonStyle(.borderless)
                    #endif
                }
            }
            
                            Button {
                    showOnboardingInstallModelView.toggle()
                } label: {
                    Label("install a model", systemImage: "arrow.down.circle.dotted")
                }
                #if os(macOS)
                .buttonStyle(.borderless)
                #endif
            }
            
            if case .api = llm.currentProvider {
                Section(header: Text("API Configuration")) {
                    Button {
                        showAPISettings.toggle()
                    } label: {
                        Label("Configure API", systemImage: "gear")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("models")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showOnboardingInstallModelView) {
            NavigationStack {
                OnboardingInstallModelView(showOnboarding: $showOnboardingInstallModelView)
                    .environment(llm)
                    .toolbar {
                        #if os(iOS) || os(visionOS)
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: { showOnboardingInstallModelView = false }) {
                                Image(systemName: "xmark")
                            }
                        }
                        #elseif os(visionOS)
                        ToolbarItem(placement: .destructiveAction) {
                            Button(action: { showOnboardingInstallModelView = false }) {
                                Text("close")
                            }
                        }
                        #endif
                    }
            }
        }
        .sheet(isPresented: $showAPISettings) {
            APISettingsView()
        }
    }
    
    private func switchModel(_ modelName: String) async {
        if let model = ModelConfiguration.availableModels.first(where: {
            $0.name == modelName
        }) {
            appManager.currentModelName = modelName
            appManager.playHaptic()
            await llm.switchModel(model)
        }
    }
}

#Preview {
    ModelsSettingsView()
}
