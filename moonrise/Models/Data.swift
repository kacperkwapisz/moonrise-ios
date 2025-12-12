//
//  Data.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/5/24.
//

import SwiftUI
import SwiftData

class AppManager: ObservableObject {
    @AppStorage("systemPrompt") var systemPrompt = "you are a helpful assistant"
    @AppStorage("appTintColor") var appTintColor: AppTintColor = .monochrome
    @AppStorage("appFontDesign") var appFontDesign: AppFontDesign = .standard
    @AppStorage("appFontSize") var appFontSize: AppFontSize = .medium
    @AppStorage("appFontWidth") var appFontWidth: AppFontWidth = .standard
    @AppStorage("currentModelName") var currentModelName: String?
    @AppStorage("shouldPlayHaptics") var shouldPlayHaptics = true
    @AppStorage("numberOfVisits") var numberOfVisits = 0
    @AppStorage("numberOfVisitsOfLastRequest") var numberOfVisitsOfLastRequest = 0
    @AppStorage("preferredProvider") var preferredProviderRaw = ProviderPreference.local.rawValue
    @AppStorage("currentAPIConfigID") var currentAPIConfigID: String?
    @AppStorage("isUsingServer") var isUsingServer = false {
        didSet {
            preferredProvider = isUsingServer ? .api : .local
        }
    }
    @AppStorage("selectedServerId") var selectedServerIdString: String?
    @AppStorage("cachedServerModels") private var cachedServerModelsData: Data?
    private let installedModelsKey = "installedModels"
    private let serversKey = "savedServers"

    @Published var installedModels: [String] = [] {
        didSet { saveInstalledModelsToUserDefaults() }
    }

    @Published var servers: [ServerConfig] = [] {
        didSet { saveServers() }
    }

    @Published var selectedServerId: UUID? {
        didSet {
            selectedServerIdString = selectedServerId?.uuidString
            // Reset current model when switching servers to avoid stale selections.
            currentModelName = nil
        }
    }

    @Published private(set) var cachedServerModels: [UUID: [String]] = [:] {
        didSet {
            if let encoded = try? JSONEncoder().encode(cachedServerModels) {
                cachedServerModelsData = encoded
            }
        }
    }

    var userInterfaceIdiom: LayoutType {
        #if os(visionOS)
        return .vision
        #elseif os(macOS)
        return .mac
        #elseif os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
        #else
        return .unknown
        #endif
    }

    var availableMemory: Double {
        let ramInBytes = ProcessInfo.processInfo.physicalMemory
        let ramInGB = Double(ramInBytes) / (1024 * 1024 * 1024)
        return ramInGB
    }

    enum LayoutType {
        case mac, phone, pad, vision, unknown
    }

    var preferredProvider: ProviderPreference {
        get { ProviderPreference(rawValue: preferredProviderRaw) ?? .local }
        set { preferredProviderRaw = newValue.rawValue }
    }

    var currentAPIConfiguration: APIConfiguration? {
        let storage = APIStorageManager.shared

        if let idString = currentAPIConfigID,
           let id = UUID(uuidString: idString),
           let config = storage.apiConfigurations.first(where: { $0.id == id }) {
            return config
        }

        if let current = storage.currentAPIConfig {
            return current
        }

        return storage.apiConfigurations.first(where: { $0.isDefault }) ?? storage.apiConfigurations.first
    }

    func setCurrentAPIConfiguration(_ config: APIConfiguration) {
        currentAPIConfigID = config.id.uuidString
        APIStorageManager.shared.setCurrentConfiguration(config)
        preferredProvider = .api
    }

    var currentServer: ServerConfig? {
        guard let id = selectedServerId else { return nil }
        return servers.first { $0.id == id }
    }

    var currentServerURL: String { currentServer?.url ?? "" }
    var currentServerAPIKey: String { currentServer?.apiKey ?? "" }

    init() {
        // Load server state first so model selection can honor it.
        loadServers()
        loadCachedModels()

        if let savedIdString = selectedServerIdString,
           let savedId = UUID(uuidString: savedIdString) {
            selectedServerId = savedId
        }

        if selectedServerId == nil && !servers.isEmpty {
            selectedServerId = servers.first?.id
        }

        loadInstalledModelsFromUserDefaults()
    }

    func incrementNumberOfVisits() {
        numberOfVisits += 1
        print("app visits: \(numberOfVisits)")
    }

    // MARK: - Installed models

    private func saveInstalledModelsToUserDefaults() {
        if let jsonData = try? JSONEncoder().encode(installedModels) {
            UserDefaults.standard.set(jsonData, forKey: installedModelsKey)
        }
    }

    private func loadInstalledModelsFromUserDefaults() {
        if let jsonData = UserDefaults.standard.data(forKey: installedModelsKey),
           let decodedArray = try? JSONDecoder().decode([String].self, from: jsonData) {
            self.installedModels = decodedArray
        } else {
            self.installedModels = []
        }
    }

    func playHaptic() {
        if shouldPlayHaptics {
            #if os(iOS)
            let impact = UIImpactFeedbackGenerator(style: .soft)
            impact.impactOccurred()
            #endif
        }
    }

    func addInstalledModel(_ model: String) {
        if !installedModels.contains(model) {
            installedModels.append(model)
        }
    }

    func modelDisplayName(_ modelName: String) -> String {
        modelName.replacingOccurrences(of: "mlx-community/", with: "").lowercased()
    }

    func getMoonPhaseIcon() -> String {
        let currentDate = Date()
        let baseDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 6))!
        let daysSinceBaseDate = Calendar.current.dateComponents([.day], from: baseDate, to: currentDate).day!
        let moonCycleLength = 29.53
        let daysIntoCycle = Double(daysSinceBaseDate).truncatingRemainder(dividingBy: moonCycleLength)

        switch daysIntoCycle {
        case 0..<1.8457:
            return "moonphase.new.moon"
        case 1.8457..<5.536:
            return "moonphase.waxing.crescent"
        case 5.536..<9.228:
            return "moonphase.first.quarter"
        case 9.228..<12.919:
            return "moonphase.waxing.gibbous"
        case 12.919..<16.610:
            return "moonphase.full.moon"
        case 16.610..<20.302:
            return "moonphase.waning.gibbous"
        case 20.302..<23.993:
            return "moonphase.last.quarter"
        case 23.993..<27.684:
            return "moonphase.waning.crescent"
        default:
            return "moonphase.new.moon"
        }
    }

    func modelSource() -> ModelSource {
        isUsingServer ? .server : .local
    }

    // MARK: - Server management

    private func loadServers() {
        guard let data = UserDefaults.standard.data(forKey: serversKey) else { return }
        if let decodedServers = try? JSONDecoder().decode([ServerConfig].self, from: data) {
            servers = decodedServers
        }
    }

    private func saveServers() {
        if let encoded = try? JSONEncoder().encode(servers) {
            UserDefaults.standard.set(encoded, forKey: serversKey)
        }
    }

    func addServer(_ server: ServerConfig) {
        let sanitized = server.sanitized()
        servers.append(sanitized)
        if selectedServerId == nil {
            selectedServerId = sanitized.id
        }
    }

    func removeServer(_ server: ServerConfig) {
        servers.removeAll { $0.id == server.id }
        if selectedServerId == server.id {
            selectedServerId = servers.first?.id
        }
    }

    func updateServer(_ server: ServerConfig) {
        if let idx = servers.firstIndex(where: { $0.id == server.id }) {
            servers[idx] = server.sanitized()
        }
    }

    func addServerWithMetadata(_ server: ServerConfig) async {
        let metadata = await fetchServerMetadata(urlString: server.url)
        let serverToSave: ServerConfig = {
            var copy = server
            if let title = metadata.title, !title.isEmpty {
                copy.name = title
            }
            return copy
        }()
        
        await MainActor.run {
            addServer(serverToSave)
            selectedServerId = serverToSave.id
        }
    }

    private func fetchServerMetadata(urlString: String) async -> (title: String?, version: String?) {
        guard var baseURL = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return (nil, nil)
        }
        baseURL.deleteLastPathComponent()

        do {
            let (data, _) = try await URLSession.shared.data(from: baseURL)
            if let html = String(data: data, encoding: .utf8) {
                let title = extractTitle(from: html)
                let version = extractVersion(from: html)
                return (title, version)
            }
        } catch {
            print("Error fetching server metadata: \(error)")
        }
        return (nil, nil)
    }

    private func extractTitle(from html: String) -> String? {
        guard let range = html.range(of: "<title>.*?</title>", options: .regularExpression) else { return nil }
        let title = html[range]
            .replacingOccurrences(of: "<title>", with: "")
            .replacingOccurrences(of: "</title>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func extractVersion(from html: String) -> String? {
        guard let range = html.range(of: "content=\".*?version.*?\"", options: .regularExpression) else { return nil }
        let version = html[range]
            .replacingOccurrences(of: "content=\"", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    private func loadCachedModels() {
        guard let data = cachedServerModelsData else { return }
        if let decoded = try? JSONDecoder().decode([UUID: [String]].self, from: data) {
            cachedServerModels = decoded
            return
        }

        // Backward compatibility for string-keyed payloads
        if let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            let mapped = decoded.compactMap { key, value -> (UUID, [String])? in
                guard let id = UUID(uuidString: key) else { return nil }
                return (id, value)
            }
            cachedServerModels = Dictionary(uniqueKeysWithValues: mapped)
        }
    }

    func updateCachedModels(serverId: UUID, models: [String]) {
        cachedServerModels[serverId] = models
    }

    func getCachedModels(for serverId: UUID) -> [String] {
        cachedServerModels[serverId] ?? []
    }
}

enum Role: String, Codable {
    case assistant
    case user
    case system
}

enum ProviderPreference: String {
    case local
    case api
}

@Model
class Message {
    @Attribute(.unique) var id: UUID
    var role: Role
    var content: String
    var timestamp: Date
    var generatingTime: TimeInterval?

    @Relationship(inverse: \Thread.messages) var thread: Thread?

    init(role: Role, content: String, thread: Thread? = nil, generatingTime: TimeInterval? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.thread = thread
        self.generatingTime = generatingTime
    }
}

@Model
final class Thread: Sendable {
    @Attribute(.unique) var id: UUID
    var title: String?
    var timestamp: Date

    @Relationship var messages: [Message] = []

    var sortedMessages: [Message] {
        messages.sorted { $0.timestamp < $1.timestamp }
    }

    init() {
        self.id = UUID()
        self.timestamp = Date()
    }
}

enum AppTintColor: String, CaseIterable {
    case monochrome, blue, brown, gray, green, indigo, mint, orange, pink, purple, red, teal, yellow

    func getColor() -> Color {
        switch self {
        case .monochrome:
            .primary
        case .blue:
            .blue
        case .red:
            .red
        case .green:
            .green
        case .yellow:
            .yellow
        case .brown:
            .brown
        case .gray:
            .gray
        case .indigo:
            .indigo
        case .mint:
            .mint
        case .orange:
            .orange
        case .pink:
            .pink
        case .purple:
            .purple
        case .teal:
            .teal
        }
    }
}

enum AppFontDesign: String, CaseIterable {
    case standard, monospaced, rounded, serif

    func getFontDesign() -> Font.Design {
        switch self {
        case .standard:
            .default
        case .monospaced:
            .monospaced
        case .rounded:
            .rounded
        case .serif:
            .serif
        }
    }
}

enum AppFontWidth: String, CaseIterable {
    case compressed, condensed, expanded, standard

    func getFontWidth() -> Font.Width {
        switch self {
        case .compressed:
            .compressed
        case .condensed:
            .condensed
        case .expanded:
            .expanded
        case .standard:
            .standard
        }
    }
}

enum AppFontSize: String, CaseIterable {
    case xsmall, small, medium, large, xlarge

    func getFontSize() -> DynamicTypeSize {
        switch self {
        case .xsmall:
            .xSmall
        case .small:
            .small
        case .medium:
            .medium
        case .large:
            .large
        case .xlarge:
            .xLarge
        }
    }
}

enum ModelSource {
    case local
    case server
}
