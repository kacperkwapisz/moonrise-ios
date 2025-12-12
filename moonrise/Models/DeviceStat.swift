//
//  DeviceStat.swift
//  fullmoon
//
//  Created by Jordan Singer on 10/4/24.
//

import Foundation
import MLXLLM
import MLX

@Observable
final class DeviceStat: @unchecked Sendable {

    // #region agent log
    private static func agentLog(hypothesisId: String, location: String, message: String, data: [String: Any] = [:]) {
        let logPath = "/Users/kacper/Vault/Personal/Coding/Projects/chippedpaws/.cursor/debug.log"
        let payload: [String: Any] = [
            "sessionId": "debug-session",
            "runId": "pre-fix",
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let url = URL(fileURLWithPath: logPath)
        var line = jsonData
        line.append(0x0a)

        if FileManager.default.fileExists(atPath: logPath), let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }
    // #endregion

    @MainActor
    var gpuUsage = { () in
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        DeviceStat.agentLog(
            hypothesisId: "H1",
            location: "DeviceStat.swift:gpuUsage",
            message: "gpuUsage init about to snapshot",
            data: ["isSimulator": isSimulator]
        )
        let snapshot = GPU.snapshot()
        DeviceStat.agentLog(
            hypothesisId: "H1",
            location: "DeviceStat.swift:gpuUsage",
            message: "gpuUsage init snapshot success",
            data: ["snapshotDescription": "\(snapshot)"]
        )
        return snapshot
    }()

    private let initialGPUSnapshot = {
        DeviceStat.agentLog(
            hypothesisId: "H2",
            location: "DeviceStat.swift:initialGPUSnapshot",
            message: "initialGPUSnapshot about to snapshot",
            data: [:]
        )
        let snapshot = GPU.snapshot()
        DeviceStat.agentLog(
            hypothesisId: "H2",
            location: "DeviceStat.swift:initialGPUSnapshot",
            message: "initialGPUSnapshot snapshot success",
            data: ["snapshotDescription": "\(snapshot)"]
        )
        return snapshot
    }()

    private var loggedFirstUpdate = false
    private var timer: Timer?

    init() {
        DeviceStat.agentLog(
            hypothesisId: "H3",
            location: "DeviceStat.swift:init",
            message: "DeviceStat init start",
            data: [:]
        )
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateGPUUsages()
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func updateGPUUsages() {
        if !loggedFirstUpdate {
            DeviceStat.agentLog(
                hypothesisId: "H3",
                location: "DeviceStat.swift:updateGPUUsages",
                message: "updateGPUUsages first tick",
                data: [:]
            )
            loggedFirstUpdate = true
        }
        let gpuSnapshotDelta = initialGPUSnapshot.delta(GPU.snapshot())
        DispatchQueue.main.async { [weak self] in
            self?.gpuUsage = gpuSnapshotDelta
        }
    }

}
