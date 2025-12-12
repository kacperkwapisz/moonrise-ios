import SwiftUI
import MarkdownUI
#if canImport(Highlightr)
import Highlightr
#endif

private let languageMap: [String: String] = [
    "js": "javascript",
    "ts": "typescript",
    "py": "python",
    "rb": "ruby",
    "shell": "bash",
    "sh": "bash",
    "jsx": "javascript",
    "tsx": "typescript",
    "yml": "yaml",
    "md": "markdown",
    "cpp": "c++",
    "objective-c": "objectivec",
    "objc": "objectivec",
    "golang": "go"
]

struct CodeBlockView: View {
    let code: String
    let language: String?
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var monoSize: CGFloat = 13
    @State private var isCopied = false

    #if canImport(Highlightr)
    private let highlightr = Highlightr()
    #endif

    private var platformBackgroundColor: Color {
        #if os(iOS)
        return Color(UIColor.secondarySystemBackground)
        #elseif os(visionOS)
        return Color(UIColor.separator)
        #elseif os(macOS)
        return Color(NSColor.secondarySystemFill)
        #endif
    }

    private var displayLanguage: String? {
        normalizeLanguage(language)
    }

    private func normalizeLanguage(_ language: String?) -> String? {
        guard let language = language?.lowercased() else { return nil }
        return languageMap[language] ?? language
    }

    private var highlightedCode: NSAttributedString? {
        #if canImport(Highlightr)
        guard let highlightr = highlightr else { return nil }
        highlightr.setTheme(to: colorScheme == .dark ? "atom-one-dark" : "atom-one-light")
        highlightr.theme.codeFont = .monospacedSystemFont(ofSize: monoSize, weight: .regular)
        return highlightr.highlight(code, as: displayLanguage)
        #else
        return nil
        #endif
    }

    private func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #else
        UIPasteboard.general.string = code
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif

        withAnimation { isCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { isCopied = false }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let displayLanguage {
                    Text(displayLanguage.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
                Spacer()
                #if os(iOS) || os(visionOS) || os(macOS)
                if !code.isEmpty {
                    ShareLink(item: code) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share code")
                }
                #endif
                Button(action: copyToClipboard) {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                        .font(.caption.weight(.medium))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(.secondary.opacity(0.12))
                        .mask(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCopied ? "Code copied" : "Copy code")
            }

            ScrollView(.horizontal, showsIndicators: true) {
                codeText
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(platformBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08))
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isCopied)
    }

    @ViewBuilder
    private var codeText: some View {
        if let highlightedCode {
            Text(AttributedString(highlightedCode))
                .font(.system(size: monoSize, weight: .regular, design: .monospaced))
                .textSelection(.enabled)
                .lineSpacing(4)
        } else {
            Text(code)
                .font(.system(size: monoSize, weight: .regular, design: .monospaced))
                .textSelection(.enabled)
                .lineSpacing(4)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        CodeBlockView(
            code: "print(\"Hello, World!\")",
            language: "swift"
        )
        CodeBlockView(
            code: "function hello() {\n  console.log('Hello World');\n}",
            language: "js"
        )
        CodeBlockView(
            code: "def hello():\n    print('Hello World')",
            language: "python"
        )
    }
    .padding()
}
