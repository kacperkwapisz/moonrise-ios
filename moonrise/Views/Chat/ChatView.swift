//
//  ChatView.swift
//  fullmoon
//
//  Created by Jordan Singer on 12/3/24.
//

import MarkdownUI
import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appManager: AppManager
    @Environment(\.modelContext) var modelContext
    @Binding var currentThread: Thread?
    @Environment(LLMEvaluator.self) var llm
    @Namespace var bottomID
    @State var showModelPicker = false
    @State var prompt = ""
    @FocusState.Binding var isPromptFocused: Bool
    @Binding var showChats: Bool
    @Binding var showSettings: Bool
    
    @State var thinkingTime: TimeInterval?
    
    @State private var generatingThreadID: UUID?
    @State private var isSending = false
    @State private var lastUserPrompt: String?

    var isPromptEmpty: Bool {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isBusy: Bool {
        isSending || llm.running
    }

    private var statusText: String? {
        if isSending {
            return "sending..."
        }

        if llm.running {
            if llm.isThinking {
                return "thinking..."
            }
            if let elapsed = llm.elapsedTime?.formatted {
                return "streaming \(elapsed)"
            }
            return "streaming..."
        }

        if llm.cancelled {
            return "stopped"
        }

        return nil
    }

    let platformBackgroundColor: Color = {
        #if os(iOS)
        return Color(UIColor.secondarySystemBackground)
        #elseif os(visionOS)
        return Color(UIColor.separator)
        #elseif os(macOS)
        return Color(NSColor.secondarySystemFill)
        #endif
    }()

    var chatInput: some View {
        HStack(alignment: .bottom, spacing: 0) {
            TextField("message", text: $prompt, axis: .vertical)
                .focused($isPromptFocused)
                .textFieldStyle(.plain)
                .accessibilityLabel("Message input")
            #if os(iOS) || os(visionOS)
                .padding(.horizontal, 16)
            #elseif os(macOS)
                .padding(.horizontal, 12)
                .onSubmit {
                    handleShiftReturn()
                }
                .submitLabel(.send)
            #endif
                .padding(.vertical, 8)
            #if os(iOS) || os(visionOS)
                .frame(minHeight: 48)
            #elseif os(macOS)
                .frame(minHeight: 32)
            #endif
            #if os(iOS)
            .onSubmit {
                isPromptFocused = true
                generate()
            }
            #endif

            if llm.running {
                stopButton
            } else {
                generateButton
            }

            if isSending && !llm.running {
                ProgressView()
                    .controlSize(.regular)
                    #if os(iOS) || os(visionOS)
                        .padding(.trailing, 8)
                        .padding(.bottom, 8)
                    #else
                        .padding(.trailing, 6)
                        .padding(.bottom, 6)
                    #endif
            }
        }
        #if os(iOS) || os(visionOS)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(platformBackgroundColor)
        )
        #elseif os(macOS)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(platformBackgroundColor)
        )
        #endif
    }

    var modelPickerButton: some View {
        Button {
            appManager.playHaptic()
            showModelPicker.toggle()
        } label: {
            Group {
                Image(systemName: "chevron.up")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #if os(iOS) || os(visionOS)
                    .frame(width: 16)
                #elseif os(macOS)
                    .frame(width: 12)
                #endif
                    .tint(.primary)
            }
            #if os(iOS) || os(visionOS)
            .frame(width: 48, height: 48)
            #elseif os(macOS)
            .frame(width: 32, height: 32)
            #endif
            .background(
                Circle()
                    .fill(platformBackgroundColor)
            )
        }
        #if os(macOS) || os(visionOS)
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel("Choose model")
    }

    var generateButton: some View {
        Button {
            generate()
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
            #if os(iOS) || os(visionOS)
                .frame(width: 24, height: 24)
            #else
                .frame(width: 16, height: 16)
            #endif
        }
        .disabled(isPromptEmpty || isBusy)
        #if os(iOS) || os(visionOS)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
        #else
            .padding(.trailing, 8)
            .padding(.bottom, 8)
        #endif
        #if os(macOS) || os(visionOS)
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel("Send message")
        .accessibilityHint("Sends your prompt to the model")
    }

    var stopButton: some View {
        Button {
            llm.stop()
        } label: {
            Image(systemName: "stop.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
            #if os(iOS) || os(visionOS)
                .frame(width: 24, height: 24)
            #else
                .frame(width: 16, height: 16)
            #endif
        }
        .disabled(llm.cancelled)
        #if os(iOS) || os(visionOS)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
        #else
            .padding(.trailing, 8)
            .padding(.bottom, 8)
        #endif
        #if os(macOS) || os(visionOS)
        .buttonStyle(.plain)
        #endif
        .accessibilityLabel("Stop generation")
    }

    @ViewBuilder
    private var statusBar: some View {
        if let statusText {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let lastUserPrompt, !isBusy {
                    Button {
                        retryLastPrompt()
                    } label: {
                        Label("Retry last", systemImage: "arrow.clockwise")
                            .labelStyle(.titleAndIcon)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .accessibilityElement(children: .combine)
        } else if let lastUserPrompt, !isBusy {
            HStack {
                Text("Ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    retryLastPrompt()
                } label: {
                    Label("Retry last", systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .accessibilityElement(children: .combine)
        }
    }

    var chatTitle: String {
        if let currentThread = currentThread {
            if let firstMessage = currentThread.sortedMessages.first {
                return firstMessage.content
            }
        }

        return "chat"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let currentThread = currentThread {
                    ConversationView(thread: currentThread, generatingThreadID: generatingThreadID)
                } else {
                    Spacer()
                    Image(systemName: appManager.getMoonPhaseIcon())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.quaternary)
                    Spacer()
                }

                HStack(alignment: .bottom) {
                    modelPickerButton
                    chatInput
                }
                .padding()
                statusBar
            }
            .navigationTitle(chatTitle)
            #if os(iOS) || os(visionOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .sheet(isPresented: $showModelPicker) {
                    NavigationStack {
                        ModelsSettingsView()
                            .environment(llm)
                        #if os(visionOS)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button(action: { showModelPicker.toggle() }) {
                                        Image(systemName: "xmark")
                                    }
                                }
                            }
                        #endif
                    }
                    #if os(iOS)
                    .presentationDragIndicator(.visible)
                    .if(appManager.userInterfaceIdiom == .phone) { view in
                        view.presentationDetents([.large])
                    }
                    #elseif os(macOS)
                    .toolbar {
                        ToolbarItem(placement: .destructiveAction) {
                            Button(action: { showModelPicker.toggle() }) {
                                Text("close")
                            }
                        }
                    }
                    #endif
                }
                .toolbar {
                    #if os(iOS) || os(visionOS)
                    if appManager.userInterfaceIdiom == .phone {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: {
                                appManager.playHaptic()
                                showChats.toggle()
                            }) {
                                Image(systemName: "list.bullet")
                            }
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            appManager.playHaptic()
                            showSettings.toggle()
                        }) {
                            Image(systemName: "gear")
                        }
                    }
                    #elseif os(macOS)
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            appManager.playHaptic()
                            showSettings.toggle()
                        }) {
                            Label("settings", systemImage: "gear")
                        }
                    }
                    #endif
                }
        }
    }

    private func generate() {
        generate(using: nil)
    }

    private func generate(using customPrompt: String?) {
        let content = (customPrompt ?? prompt).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        if currentThread == nil {
            let newThread = Thread()
            currentThread = newThread
            modelContext.insert(newThread)
            try? modelContext.save()
        }

        guard let currentThread else { return }
        generatingThreadID = currentThread.id
        lastUserPrompt = content
        isSending = true

        Task { @MainActor in
            if customPrompt == nil {
                prompt = ""
            }
            appManager.playHaptic()
            sendMessage(Message(role: .user, content: content, thread: currentThread))
            isPromptFocused = true

            let resolvedModelName: String? = {
                if appManager.isUsingServer {
                    return appManager.currentModelName ?? llm.selectedServerModel
                }
                if appManager.preferredProvider == .api {
                    return appManager.currentAPIConfiguration?.modelName ?? appManager.currentModelName
                }
                return appManager.currentModelName
            }()

            guard let modelName = resolvedModelName else {
                sendMessage(Message(role: .assistant, content: "No model selected. Choose a model in settings first.", thread: currentThread))
                generatingThreadID = nil
                isSending = false
                return
            }

            let output = await llm.generate(modelName: modelName, thread: currentThread, systemPrompt: appManager.systemPrompt)
            sendMessage(Message(role: .assistant, content: output, thread: currentThread, generatingTime: llm.thinkingTime))
            generatingThreadID = nil
            isSending = false
        }
    }

    private func retryLastPrompt() {
        generate(using: lastUserPrompt)
    }

    private func sendMessage(_ message: Message) {
        appManager.playHaptic()
        modelContext.insert(message)
        try? modelContext.save()
    }

    #if os(macOS)
    private func handleShiftReturn() {
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            prompt.append("\n")
            isPromptFocused = true
        } else {
            generate()
        }
    }
    #endif
}

#Preview {
    @FocusState var isPromptFocused: Bool
    ChatView(currentThread: .constant(nil), isPromptFocused: $isPromptFocused, showChats: .constant(false), showSettings: .constant(false))
}
