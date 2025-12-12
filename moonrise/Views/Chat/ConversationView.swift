//
//  ConversationView.swift
//  fullmoon
//
//  Created by Xavier on 16/12/2024.
//

import MarkdownUI
import SwiftUI

extension TimeInterval {
    var formatted: String {
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60

        if minutes > 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        } else {
            return "\(seconds)s"
        }
    }
}

struct MessageView: View {
    @Environment(LLMEvaluator.self) var llm
    @State private var collapsed = true
    let message: Message

    var isThinking: Bool {
        !message.content.contains("</think>")
    }

    func processThinkingContent(_ content: String) -> (String?, String?) {
        guard let startRange = content.range(of: "<think>") else {
            // No <think> tag, return entire content as the second part
            return (nil, content.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let endRange = content.range(of: "</think>") else {
            // No </think> tag, return content after <think> without the tag
            let thinking = String(content[startRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (thinking, nil)
        }

        let thinking = String(content[startRange.upperBound ..< endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let afterThink = String(content[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

        return (thinking, afterThink.isEmpty ? nil : afterThink)
    }

    var time: String {
        if isThinking, llm.running, let elapsedTime = llm.elapsedTime {
            if isThinking {
                return "(\(elapsedTime.formatted))"
            }
            if let thinkingTime = llm.thinkingTime {
                return thinkingTime.formatted
            }
        } else if let generatingTime = message.generatingTime {
            return "\(generatingTime.formatted)"
        }

        return "0s"
    }

    var thinkingLabel: some View {
        HStack {
            Button {
                collapsed.toggle()
            } label: {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 12))
                    .fontWeight(.medium)
            }

            Text("\(isThinking ? "thinking..." : "thought for") \(time)")
                .italic()
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer() }

            if message.role == .assistant {
                let (thinking, afterThink) = processThinkingContent(message.content)
                VStack(alignment: .leading, spacing: 16) {
                    if let thinking {
                        VStack(alignment: .leading, spacing: 12) {
                            thinkingLabel
                            if !collapsed {
                                if !thinking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    HStack(spacing: 12) {
                                        Capsule()
                                            .frame(width: 2)
                                            .padding(.vertical, 1)
                                            .foregroundStyle(.fill)
                                        Markdown(thinking)
                                            .textSelection(.enabled)
                                            .markdownTheme(markdownTheme(foregroundColor: .secondary))
                                    }
                                    .padding(.leading, 5)
                                }
                            }
                        }
                        .contentShape(.rect)
                        .onTapGesture {
                            collapsed.toggle()
                            if isThinking {
                                llm.collapsed = collapsed
                            }
                        }
                    }

                    if let afterThink {
                        Markdown(afterThink)
                            .textSelection(.enabled)
                            .markdownTheme(markdownTheme(foregroundColor: .primary))
                    }
                }
                .padding(.trailing, 48)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Markdown(message.content)
                        .textSelection(.enabled)
                        .markdownTheme(markdownTheme(foregroundColor: .primary))
                }
                #if os(iOS) || os(visionOS)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                #else
                    .padding(.horizontal, 16 * 2 / 3)
                    .padding(.vertical, 8)
                #endif
                    .background(platformBackgroundColor)
                #if os(iOS) || os(visionOS)
                    .mask(RoundedRectangle(cornerRadius: 24))
                #elseif os(macOS)
                    .mask(RoundedRectangle(cornerRadius: 16))
                #endif
                    .padding(.leading, 48)
            }

            if message.role == .assistant { Spacer() }
        }
        .onAppear {
            if llm.running {
                collapsed = false
            }
        }
        .onChange(of: llm.elapsedTime) {
            if isThinking {
                llm.thinkingTime = llm.elapsedTime
            }
        }
        .onChange(of: isThinking) {
            if llm.running {
                llm.isThinking = isThinking
            }
        }
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
    
    private func markdownTheme(foregroundColor: Color) -> Theme {
        Theme()
            .text {
                ForegroundColor(foregroundColor)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.85))
            }
            .codeBlock { content in
                CodeBlockView(code: content.content, language: content.language)
            }
    }
}

struct ConversationView: View {
    @EnvironmentObject var appManager: AppManager
    @Environment(LLMEvaluator.self) var llm
    let thread: Thread
    let generatingThreadID: UUID?

    @State private var scrollID: String?
    @State private var scrollInterrupted = false
    @State private var isAtBottom = true

    var body: some View {
        ScrollViewReader { scrollView in
            ZStack(alignment: .bottomTrailing) {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(thread.sortedMessages) { message in
                            MessageView(message: message)
                                .padding()
                                .id(message.id.uuidString)
                        }

                        if llm.running && !llm.output.isEmpty && thread.id == generatingThreadID {
                            VStack {
                                MessageView(message: Message(role: .assistant, content: llm.output + " 🌕"))
                            }
                            .padding()
                            .id("output")
                            .onAppear {
                                print("output appeared")
                                scrollInterrupted = false // reset interruption when a new output begins
                            }
                        }

                        Rectangle()
                            .fill(.clear)
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $scrollID, anchor: .bottom)
                .onChange(of: llm.output) { _, _ in
                    // auto scroll to bottom
                    if !scrollInterrupted {
                        withAnimation(.easeOut(duration: 0.2)) {
                            scrollView.scrollTo("bottom", anchor: .bottom)
                        }
                    }

                    if !llm.isThinking {
                        appManager.playHaptic()
                    }
                }
                .onChange(of: scrollID) { _, newValue in
                    let atBottom = newValue == "bottom" || newValue == thread.sortedMessages.last?.id.uuidString
                    isAtBottom = atBottom
                    if llm.running && !atBottom {
                        scrollInterrupted = true
                    } else if atBottom {
                        scrollInterrupted = false
                    }
                }
                .onChange(of: llm.running) { _, running in
                    if !running {
                        scrollInterrupted = false
                        isAtBottom = true
                    }
                }

                if scrollInterrupted && !isAtBottom {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                            scrollView.scrollTo("bottom", anchor: .bottom)
                        }
                        scrollInterrupted = false
                        scrollID = "bottom"
                    } label: {
                        Label("Jump to latest", systemImage: "chevron.down")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .mask(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                    .shadow(radius: 3)
                    .accessibilityLabel("Jump to latest message")
                }
            }
        }
        .defaultScrollAnchor(.bottom)
        #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
        #endif
    }
}

#Preview {
    ConversationView(thread: Thread(), generatingThreadID: nil)
        .environment(LLMEvaluator(appManager: AppManager()))
        .environmentObject(AppManager())
}
