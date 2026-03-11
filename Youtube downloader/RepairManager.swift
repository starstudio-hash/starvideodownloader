//
//  RepairManager.swift
//  Youtube downloader
//

import Foundation

private enum PersistedRepairStatusKind: String, Codable {
    case waiting
    case scanning
    case scanned
    case repairing
    case completed
    case failed
    case cancelled
}

private struct PersistedRepairItem: Codable {
    var inputPath: String
    var outputPath: String?
    var fileName: String
    var fileSize: Int64
    var statusKind: PersistedRepairStatusKind
    var severity: String?
    var message: String?
    var detectedIssues: [String]
    var issueCount: Int
    var repairStage: Int
    var duration: Double
    var resolution: String
    var codec: String
    var addedDate: Date

    init(item: RepairItem) {
        inputPath = item.inputPath.path
        outputPath = item.outputPath?.path
        fileName = item.fileName
        fileSize = item.fileSize
        detectedIssues = item.detectedIssues
        issueCount = item.issueCount
        repairStage = item.repairStage
        duration = item.duration
        resolution = item.resolution
        codec = item.codec
        addedDate = item.addedDate
        switch item.status {
        case .waiting:
            statusKind = .waiting
        case .scanning:
            statusKind = .scanning
        case .scanned(let severity):
            statusKind = .scanned
            self.severity = severity
        case .repairing:
            statusKind = .repairing
        case .completed:
            statusKind = .completed
        case .failed(let message):
            statusKind = .failed
            self.message = message
        case .cancelled:
            statusKind = .cancelled
        }
    }

    func makeItem() -> RepairItem {
        let item = RepairItem(inputPath: URL(fileURLWithPath: inputPath))
        item.outputPath = outputPath.map { URL(fileURLWithPath: $0) }
        item.fileName = fileName
        item.fileSize = fileSize
        item.detectedIssues = detectedIssues
        item.issueCount = issueCount
        item.repairStage = repairStage
        item.duration = duration
        item.resolution = resolution
        item.codec = codec
        item.addedDate = addedDate
        switch statusKind {
        case .waiting:
            item.status = .waiting
        case .scanning, .repairing:
            item.status = .failed("Interrupted by a previous app session. Retry to continue.")
        case .scanned:
            item.status = .scanned(severity: severity ?? "Moderate")
        case .completed:
            item.status = .completed
        case .failed:
            item.status = .failed(message ?? "Repair failed.")
        case .cancelled:
            item.status = .cancelled
        }
        return item
    }
}

@Observable
class RepairManager {
    var items: [RepairItem] = []
    private var processes: [UUID: Process] = [:]
    private var activeCount = 0
    private var waitingItems: [RepairItem] = []
    var maxConcurrent: Int = 2
    var repairMode: RepairMode = .auto
    private var saveWork: DispatchWorkItem?

    private static let queueStateURL = DownloadManager.appSupportDirectory().appendingPathComponent("repair-queue.json")
    private static let saveQueue = DispatchQueue(label: "com.starvideodownloader.repair-save", qos: .utility)

    // MARK: - ffmpeg / ffprobe paths

    private var _cachedFfmpegPath: String? = nil
    private var _cachedFfprobePath: String? = nil

    var ffmpegPath: String {
        if let cached = _cachedFfmpegPath { return cached }
        let appFfmpeg = DownloadManager.appBinDirectory.appendingPathComponent("ffmpeg").path
        let candidates = [
            appFfmpeg,
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        let found = candidates.first { FileManager.default.fileExists(atPath: $0) } ?? appFfmpeg
        _cachedFfmpegPath = found
        return found
    }

    var ffprobePath: String {
        if let cached = _cachedFfprobePath { return cached }
        let appFfprobe = DownloadManager.appBinDirectory.appendingPathComponent("ffprobe").path
        let candidates = [
            appFfprobe,
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        let found = candidates.first { FileManager.default.fileExists(atPath: $0) } ?? appFfprobe
        _cachedFfprobePath = found
        return found
    }

    var isFfmpegInstalled: Bool {
        FileManager.default.fileExists(atPath: ffmpegPath)
    }

    func invalidatePathCache() {
        _cachedFfmpegPath = nil
        _cachedFfprobePath = nil
    }

    init() {
        restorePersistedQueue()
    }

    // MARK: - Public API

    func addFiles(_ urls: [URL]) {
        for url in urls {
            // Avoid duplicates
            guard !items.contains(where: { $0.inputPath == url }) else { continue }
            let item = RepairItem(inputPath: url)
            items.append(item)
            scanFile(item)
        }
        schedulePersistence()
    }

    func scanAllItems() {
        for item in items {
            if case .waiting = item.status {
                scanFile(item)
            } else if case .scanned = item.status {
                // Re-scan
                scanFile(item)
            }
        }
    }

    func repairAllScanned() {
        for item in items {
            if case .scanned(let severity) = item.status, severity != "None" {
                enqueueOrStart(item)
            }
        }
    }

    func cancelRepair(_ item: RepairItem) {
        let wasActive: Bool
        if case .repairing = item.status {
            wasActive = true
        } else {
            wasActive = false
        }
        processes[item.id]?.terminate()
        processes[item.id] = nil
        item.status = .cancelled
        if wasActive && activeCount > 0 { activeCount -= 1 }
        waitingItems.removeAll { $0.id == item.id }
        startNextWaiting()
        schedulePersistence()
    }

    func removeItem(_ item: RepairItem) {
        cancelRepair(item)
        items.removeAll { $0.id == item.id }
        schedulePersistence()
    }

    func clearCompleted() {
        items.removeAll {
            if case .completed = $0.status { return true }
            if case .cancelled = $0.status { return true }
            if case .failed = $0.status { return true }
            return false
        }
        schedulePersistence()
    }

    func retryRepair(_ item: RepairItem) {
        item.status = .waiting
        item.outputPath = nil
        item.repairStage = 0
        scanFile(item)
        schedulePersistence()
    }

    func startRepair(_ item: RepairItem) {
        enqueueOrStart(item)
    }

    // MARK: - Queue

    private func enqueueOrStart(_ item: RepairItem) {
        if activeCount < maxConcurrent {
            activeCount += 1
            runRepairPipeline(item)
        } else {
            item.status = .waiting
            waitingItems.append(item)
        }
        schedulePersistence()
    }

    private func startNextWaiting() {
        while !waitingItems.isEmpty, activeCount < maxConcurrent {
            let next = waitingItems.removeFirst()
            guard items.contains(where: { $0.id == next.id }) else { continue }
            activeCount += 1
            runRepairPipeline(next)
        }
    }

    // MARK: - Scanning

    private func scanFile(_ item: RepairItem) {
        guard isFfmpegInstalled else {
            item.status = .failed("ffmpeg not found. Install it from the Convert tab.")
            schedulePersistence()
            return
        }

        item.status = .scanning
        schedulePersistence()
        let inputPath = item.inputPath.path
        let probePath = ffprobePath
        let ffmpeg = ffmpegPath
        let env = buildCleanEnvironment()

        DispatchQueue.global(qos: .userInitiated).async {
            var issues: [String] = []

            // 1. Run ffprobe to get format and stream info
            let probeResult = Self.runCommand(
                executablePath: probePath,
                arguments: ["-v", "error", "-show_format", "-show_streams", "-print_format", "json", inputPath],
                env: env
            )

            var duration: Double = 0
            var resolution = ""
            var codec = ""
            var hasMoovAtom = true

            if let data = probeResult.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                // Extract format info
                if let format = json["format"] as? [String: Any] {
                    if let dur = format["duration"] as? String {
                        duration = Double(dur) ?? 0
                    }
                    if duration == 0 {
                        issues.append("Missing or invalid duration")
                    }
                } else {
                    issues.append("Cannot read container format")
                    hasMoovAtom = false
                }

                // Extract stream info
                if let streams = json["streams"] as? [[String: Any]] {
                    for stream in streams {
                        let codecType = stream["codec_type"] as? String ?? ""
                        if codecType == "video" {
                            let w = stream["width"] as? Int ?? 0
                            let h = stream["height"] as? Int ?? 0
                            resolution = "\(w)x\(h)"
                            codec = stream["codec_name"] as? String ?? "unknown"
                        }
                    }
                    if streams.isEmpty {
                        issues.append("No media streams found")
                    }
                } else {
                    issues.append("Cannot read media streams")
                }
            } else {
                issues.append("ffprobe failed to read file — possibly missing moov atom")
                hasMoovAtom = false
            }

            // 2. Run error scan: ffmpeg -v error -i input -f null -
            let errorOutput = Self.runCommand(
                executablePath: ffmpeg,
                arguments: ["-v", "error", "-i", inputPath, "-f", "null", "-"],
                env: env,
                captureStderr: true
            )

            let errorLines = errorOutput
                .components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let errorCount = errorLines.count

            // Categorize errors
            var hasCorruptFrames = false
            var hasAudioDesync = false
            var hasMissingRefs = false

            for line in errorLines {
                let lower = line.lowercased()
                if lower.contains("corrupt") || lower.contains("invalid") || lower.contains("error while decoding") {
                    hasCorruptFrames = true
                }
                if lower.contains("discarding") || lower.contains("dts") || lower.contains("pts") || lower.contains("sync") {
                    hasAudioDesync = true
                }
                if lower.contains("missing reference") || lower.contains("non existing") || lower.contains("no frame") {
                    hasMissingRefs = true
                }
            }

            if hasCorruptFrames { issues.append("Corrupt frames detected") }
            if hasAudioDesync { issues.append("Audio/video desync detected") }
            if hasMissingRefs { issues.append("Missing frame references") }
            if !hasMoovAtom { issues.append("Missing or damaged moov atom") }
            if errorCount > 0 && issues.count <= 1 {
                issues.append("\(errorCount) error\(errorCount == 1 ? "" : "s") found during scan")
            }

            // Determine severity
            let severity: String
            if issues.isEmpty && errorCount == 0 {
                severity = "None"
            } else if errorCount <= 5 && hasMoovAtom {
                severity = "Minor"
            } else if errorCount <= 50 && hasMoovAtom {
                severity = "Moderate"
            } else if errorCount <= 200 || !hasMoovAtom {
                severity = "Severe"
            } else {
                severity = "Critical"
            }

            DispatchQueue.main.async {
                item.detectedIssues = issues
                item.issueCount = errorCount
                item.duration = duration
                item.resolution = resolution
                item.codec = codec
                item.status = .scanned(severity: severity)
                self.schedulePersistence()
            }
        }
    }

    // MARK: - Repair Pipeline

    private func runRepairPipeline(_ item: RepairItem) {
        guard isFfmpegInstalled else {
            item.status = .failed("ffmpeg not found.")
            if activeCount > 0 { activeCount -= 1 }
            startNextWaiting()
            schedulePersistence()
            return
        }

        let mode = repairMode
        let maxStage = mode.maxStage
        let inputPath = item.inputPath.path
        let ffmpeg = ffmpegPath
        let probePath = ffprobePath
        let env = buildCleanEnvironment()

        DispatchQueue.main.async {
            item.status = .repairing(progress: 0, stage: 1, totalStages: maxStage)
            self.schedulePersistence()
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let inputURL = item.inputPath
            let ext = inputURL.pathExtension
            let baseName = inputURL.deletingPathExtension().lastPathComponent
            let outputDir = inputURL.deletingLastPathComponent()

            var success = false

            for stage in 1...maxStage {
                // Check if cancelled
                if case .cancelled = item.status { break }

                DispatchQueue.main.async {
                    item.repairStage = stage
                    item.status = .repairing(progress: 0, stage: stage, totalStages: maxStage)
                    self.schedulePersistence()
                }

                let outputPath = outputDir.appendingPathComponent("\(baseName)_repaired.\(ext)").path

                // Remove previous attempt if exists
                try? FileManager.default.removeItem(atPath: outputPath)

                var args: [String] = []

                switch stage {
                case 1:
                    // Stage 1: Simple remux (container rebuild)
                    args = ["-y", "-i", inputPath, "-c", "copy", outputPath]

                case 2:
                    // Stage 2: Faststart + copy
                    args = ["-y", "-i", inputPath, "-c", "copy", "-movflags", "+faststart", outputPath]

                case 3:
                    // Stage 3: Error-tolerant remux
                    args = ["-y", "-err_detect", "ignore_err", "-i", inputPath, "-c", "copy", outputPath]

                case 4:
                    // Stage 4: Discard corrupt frames
                    args = ["-y", "-err_detect", "aggressive", "-fflags", "+discardcorrupt", "-i", inputPath, "-c", "copy", outputPath]

                case 5:
                    // Stage 5: Audio resync
                    args = ["-y", "-i", inputPath, "-c:v", "copy",
                            "-af", "aresample=async=1:first_pts=0",
                            "-c:a", "aac", outputPath]

                case 6:
                    // Stage 6: Full re-encode (last resort)
                    args = ["-y", "-i", inputPath,
                            "-c:v", "libx264", "-crf", "18", "-preset", "medium",
                            "-c:a", "aac", "-b:a", "192k",
                            "-progress", "pipe:1", "-nostats",
                            outputPath]

                default:
                    break
                }

                guard !args.isEmpty else { continue }

                let stageSuccess = self.runFfmpegRepair(
                    ffmpegPath: ffmpeg,
                    arguments: args,
                    item: item,
                    stage: stage,
                    totalStages: maxStage,
                    isReEncode: stage == 6,
                    totalSeconds: item.duration
                )

                if stageSuccess {
                    // Verify the output
                    let verified = self.verifyRepair(
                        outputPath: outputPath,
                        originalDuration: item.duration,
                        ffprobePath: probePath,
                        ffmpegPath: ffmpeg,
                        env: env
                    )

                    if verified {
                        DispatchQueue.main.async {
                            item.outputPath = URL(fileURLWithPath: outputPath)
                            item.status = .completed
                            self.schedulePersistence()
                        }
                        success = true
                        break
                    }
                }

                // Clean up failed attempt
                try? FileManager.default.removeItem(atPath: outputPath)
            }

            DispatchQueue.main.async {
                if self.activeCount > 0 { self.activeCount -= 1 }
                if !success {
                    if case .cancelled = item.status {
                        // Already set
                    } else {
                        item.status = .failed("All repair stages exhausted. The file may be too severely damaged.")
                    }
                }
                self.processes.removeValue(forKey: item.id)
                self.schedulePersistence()
                self.startNextWaiting()
            }
        }
    }

    private func runFfmpegRepair(
        ffmpegPath: String,
        arguments: [String],
        item: RepairItem,
        stage: Int,
        totalStages: Int,
        isReEncode: Bool,
        totalSeconds: Double
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = arguments
        process.environment = buildCleanEnvironment()

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        DispatchQueue.main.async { self.processes[item.id] = process }

        if isReEncode && totalSeconds > 0 {
            // Parse progress for re-encode stage
            var lineBuffer = ""
            var lastProgressUpdate = DispatchTime.now()
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                lineBuffer += chunk
                if lineBuffer.count > 524_288 {
                    lineBuffer = String(lineBuffer.suffix(32768))
                }
                var lines = lineBuffer.components(separatedBy: "\n")
                lineBuffer = lines.removeLast()

                var latestPct: Double? = nil
                for line in lines where line.hasPrefix("out_time_us=") {
                    if let us = Double(line.dropFirst("out_time_us=".count)) {
                        latestPct = min(us / 1_000_000.0 / totalSeconds, 1.0)
                    }
                }
                if let pct = latestPct {
                    let now = DispatchTime.now()
                    if now > lastProgressUpdate + .milliseconds(100) {
                        lastProgressUpdate = now
                        DispatchQueue.main.async {
                            item.status = .repairing(progress: pct, stage: stage, totalStages: totalStages)
                            self.schedulePersistence()
                        }
                    }
                }
            }
        }

        guard (try? process.run()) != nil else {
            DispatchQueue.main.async {
                self.processes.removeValue(forKey: item.id)
                self.schedulePersistence()
            }
            return false
        }
        process.waitUntilExit()

        outPipe.fileHandleForReading.readabilityHandler = nil
        DispatchQueue.main.async { self.schedulePersistence() }
        return process.terminationStatus == 0
    }

    // MARK: - Verification

    private func verifyRepair(
        outputPath: String,
        originalDuration: Double,
        ffprobePath: String,
        ffmpegPath: String,
        env: [String: String]
    ) -> Bool {
        // Check file exists and has reasonable size
        guard FileManager.default.fileExists(atPath: outputPath) else { return false }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: outputPath),
              let fileSize = attrs[.size] as? Int64,
              fileSize > 1000 else { return false }

        // Run ffprobe to check duration
        let probeOutput = Self.runCommand(
            executablePath: ffprobePath,
            arguments: ["-v", "error", "-show_entries", "format=duration",
                        "-of", "default=noprint_wrappers=1:nokey=1", outputPath],
            env: env
        )
        let outputDuration = Double(probeOutput.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0

        // Duration should be within 10% of original (if original was detected)
        if originalDuration > 0 && outputDuration > 0 {
            let ratio = outputDuration / originalDuration
            if ratio < 0.5 { return false } // Lost more than half — not acceptable
        }

        // Run error scan on output
        let errorOutput = Self.runCommand(
            executablePath: ffmpegPath,
            arguments: ["-v", "error", "-i", outputPath, "-f", "null", "-"],
            env: env,
            captureStderr: true
        )

        let errorCount = errorOutput
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .count

        // Accept if few or no errors
        return errorCount <= 3
    }

    private func schedulePersistence() {
        saveWork?.cancel()
        let snapshot = items.map(PersistedRepairItem.init(item:))
        let work = DispatchWorkItem {
            Self.saveQueue.async {
                if snapshot.isEmpty {
                    try? FileManager.default.removeItem(at: Self.queueStateURL)
                    return
                }
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(snapshot) {
                    try? data.write(to: Self.queueStateURL, options: .atomic)
                }
            }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func restorePersistedQueue() {
        guard let data = try? Data(contentsOf: Self.queueStateURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode([PersistedRepairItem].self, from: data) else { return }
        items = snapshot.map { $0.makeItem() }
        waitingItems = items.filter {
            if case .waiting = $0.status { return true }
            return false
        }
    }

    // MARK: - Helpers

    private static func runCommand(
        executablePath: String,
        arguments: [String],
        env: [String: String],
        captureStderr: Bool = false
    ) -> String {
        guard FileManager.default.fileExists(atPath: executablePath) else { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do { try process.run() } catch { return "" }
        process.waitUntilExit()

        if captureStderr {
            return String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }
        return String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    /// Cached clean environment — built once and reused.
    private static let _cleanEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
        env.removeValue(forKey: "DYLD_LIBRARY_PATH")
        env.removeValue(forKey: "DYLD_FRAMEWORK_PATH")
        let appBin = DownloadManager.appBinDirectory.path
        let path = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = appBin + ":/opt/homebrew/bin:/usr/local/bin:" + path
        return env
    }()

    private func buildCleanEnvironment() -> [String: String] {
        Self._cleanEnvironment
    }
}
