//
//  ConversionManager.swift
//  Youtube downloader
//

import Foundation

@Observable
class ConversionManager {
    var items: [ConversionItem] = []
    private var processes: [UUID: Process] = [:]
    private var activeCount = 0
    private var waitingItems: [ConversionItem] = []
    var maxConcurrent: Int = 2

    // MARK: - ffmpeg path

    private var _cachedFfmpegPath: String? = nil

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

    var isFfmpegInstalled: Bool {
        FileManager.default.fileExists(atPath: ffmpegPath)
    }

    func invalidateFfmpegPathCache() {
        _cachedFfmpegPath = nil
    }

    // MARK: - Public API

    func addFiles(_ urls: [URL], videoCodec: VideoCodec, audioCodec: AudioCodec, quality: EncodingQuality, outputFormat: String, processingOptions: VideoProcessingOptions = VideoProcessingOptions(), audioOnly: Bool = false) {
        for url in urls {
            let item = ConversionItem(
                inputPath: url,
                videoCodec: videoCodec,
                audioCodec: audioCodec,
                encodingQuality: quality,
                outputFormat: outputFormat,
                processingOptions: processingOptions,
                audioOnly: audioOnly
            )
            items.append(item)
            enqueueOrStart(item)
        }
    }

    func cancelConversion(_ item: ConversionItem) {
        let wasActive: Bool
        if case .converting = item.status {
            wasActive = true
        } else if case .waiting = item.status {
            wasActive = false
        } else {
            wasActive = false
        }
        processes[item.id]?.terminate()
        processes[item.id] = nil
        item.status = .cancelled
        if wasActive && activeCount > 0 { activeCount -= 1 }
        waitingItems.removeAll { $0.id == item.id }
        startNextWaiting()
    }

    func removeItem(_ item: ConversionItem) {
        cancelConversion(item)
        items.removeAll { $0.id == item.id }
    }

    func retryConversion(_ item: ConversionItem) {
        item.status = .waiting
        item.outputPath = nil
        enqueueOrStart(item)
    }

    // MARK: - Queue

    private func enqueueOrStart(_ item: ConversionItem) {
        if activeCount < maxConcurrent {
            activeCount += 1
            startConversion(item)
        } else {
            item.status = .waiting
            waitingItems.append(item)
        }
    }

    private func startNextWaiting() {
        while !waitingItems.isEmpty, activeCount < maxConcurrent {
            let next = waitingItems.removeFirst()
            guard items.contains(where: { $0.id == next.id }) else { continue }
            activeCount += 1
            startConversion(next)
        }
    }

    // MARK: - Conversion

    private func startConversion(_ item: ConversionItem) {
        guard isFfmpegInstalled else {
            item.status = .failed("ffmpeg not found. Install it from the Convert tab.")
            if activeCount > 0 { activeCount -= 1 }
            startNextWaiting()
            return
        }

        item.status = .converting(progress: 0)

        let input = item.inputPath.path
        let vidCodec = item.videoCodec
        let audCodec = item.audioCodec
        let quality = item.encodingQuality
        let outputExt = item.outputFormat
        let ffmpeg = ffmpegPath

        // Build output path — same directory, new extension
        let outputURL = item.inputPath.deletingPathExtension().appendingPathExtension(outputExt)
        // If output would overwrite input, add suffix
        let finalOutput: URL
        if outputURL.path == item.inputPath.path {
            let name = item.inputPath.deletingPathExtension().lastPathComponent
            let dir = item.inputPath.deletingLastPathComponent()
            finalOutput = dir.appendingPathComponent("\(name)_converted.\(outputExt)")
        } else {
            finalOutput = outputURL
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Get duration for progress
            let ffprobePath = ffmpeg.replacingOccurrences(of: "ffmpeg", with: "ffprobe")
            let totalSeconds = Self.probeDuration(filePath: input, ffprobePath: ffprobePath, env: self.buildCleanEnvironment())

            // Build ffmpeg args
            var codecArgs: [String] = []

            let videoEncoderName: String
            if item.audioOnly {
                // Audio-only extraction: drop video, copy audio
                videoEncoderName = "copy" // placeholder, we'll use -vn
                codecArgs += ["-vn", "-c:a", audCodec.ffmpegEncoder]
                codecArgs += audCodec.qualityArgs(quality: quality)
            } else {
                // Video codec
                if vidCodec == .copy {
                    videoEncoderName = "copy"
                } else if let hw = vidCodec.hardwareEncoder {
                    videoEncoderName = hw
                    codecArgs += vidCodec.hardwareQualityArgs(quality: quality)
                } else if let sw = vidCodec.softwareEncoder {
                    videoEncoderName = sw
                    codecArgs += vidCodec.softwareQualityArgs(quality: quality)
                } else {
                    videoEncoderName = "copy"
                }

                // Audio codec
                codecArgs += ["-c:a", audCodec.ffmpegEncoder]
                codecArgs += audCodec.qualityArgs(quality: quality)

                // Video processing options
                let procArgs = item.processingOptions.buildFfmpegArgs()
                codecArgs += procArgs
            }

            let success = self.runFfmpeg(
                ffmpegPath: ffmpeg,
                input: input,
                output: finalOutput.path,
                videoCodec: item.audioOnly ? "none" : videoEncoderName,
                codecArgs: codecArgs,
                totalSeconds: totalSeconds,
                item: item
            )

            DispatchQueue.main.async {
                if self.activeCount > 0 { self.activeCount -= 1 }
                if success {
                    item.outputPath = finalOutput
                    item.status = .completed
                } else if case .cancelled = item.status {
                    // Already set
                } else {
                    item.status = .failed("Conversion failed. Check that the input file is a valid media file.")
                }
                self.startNextWaiting()
            }
        }
    }

    private func runFfmpeg(
        ffmpegPath: String,
        input: String,
        output: String,
        videoCodec: String,
        codecArgs: [String],
        totalSeconds: Double,
        item: ConversionItem
    ) -> Bool {
        DispatchQueue.main.async { item.status = .converting(progress: 0) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        var ffmpegArgs = ["-y", "-i", input]
        if videoCodec != "none" {
            ffmpegArgs += ["-c:v", videoCodec]
        }
        ffmpegArgs += codecArgs
        // -movflags +faststart is only valid for MP4/MOV containers
        let ext = (output as NSString).pathExtension.lowercased()
        if ext == "mp4" || ext == "mov" || ext == "m4a" {
            ffmpegArgs += ["-movflags", "+faststart"]
        }
        ffmpegArgs += ["-progress", "pipe:1", "-nostats", output]
        process.arguments = ffmpegArgs
        process.environment = buildCleanEnvironment()

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        DispatchQueue.main.async { self.processes[item.id] = process }

        var lineBuffer = ""
        var lastProgressUpdate = DispatchTime.now()
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard self != nil else { return }
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            lineBuffer += chunk
            if lineBuffer.count > 524_288 {
                lineBuffer = String(lineBuffer.suffix(32768))
            }
            var lines = lineBuffer.components(separatedBy: "\n")
            lineBuffer = lines.removeLast()
            // Find the last progress value and throttle UI updates to ~10/sec
            var latestPct: Double? = nil
            for line in lines where line.hasPrefix("out_time_us=") {
                if let us = Double(line.dropFirst("out_time_us=".count)) {
                    latestPct = totalSeconds > 0 ? min(us / 1_000_000.0 / totalSeconds, 1.0) : 0
                }
            }
            if let pct = latestPct {
                let now = DispatchTime.now()
                if now > lastProgressUpdate + .milliseconds(100) {
                    lastProgressUpdate = now
                    DispatchQueue.main.async { item.status = .converting(progress: pct) }
                }
            }
        }

        guard (try? process.run()) != nil else {
            DispatchQueue.main.async { self.processes.removeValue(forKey: item.id) }
            return false
        }
        process.waitUntilExit()
        outPipe.fileHandleForReading.readabilityHandler = nil
        DispatchQueue.main.async { self.processes.removeValue(forKey: item.id) }
        return process.terminationStatus == 0
    }

    // MARK: - Concatenation

    func concatenateFiles(_ urls: [URL], outputFormat: String) {
        guard urls.count >= 2 else { return }
        guard isFfmpegInstalled else { return }

        let item = ConversionItem(
            inputPath: urls[0],
            videoCodec: .copy,
            audioCodec: .copy,
            encodingQuality: .medium,
            outputFormat: outputFormat
        )
        item.title = "Concatenated (\(urls.count) files)"
        items.append(item)
        item.status = .converting(progress: 0)

        let ffmpeg = ffmpegPath
        let allPaths = urls

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Create temporary concat list file
            let tmpDir = FileManager.default.temporaryDirectory
            let listFile = tmpDir.appendingPathComponent("concat_\(item.id.uuidString).txt")
            let listContent = allPaths.map { "file '\($0.path)'" }.joined(separator: "\n")
            try? listContent.write(to: listFile, atomically: true, encoding: .utf8)

            let outputDir = urls[0].deletingLastPathComponent()
            let outputPath = outputDir.appendingPathComponent("concatenated.\(outputFormat)").path

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments = [
                "-y", "-f", "concat", "-safe", "0",
                "-i", listFile.path,
                "-c", "copy",
                outputPath
            ]
            process.environment = self.buildCleanEnvironment()
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            DispatchQueue.main.async { self.processes[item.id] = process }

            guard (try? process.run()) != nil else {
                try? FileManager.default.removeItem(at: listFile)
                DispatchQueue.main.async {
                    self.processes.removeValue(forKey: item.id)
                    item.status = .failed("Failed to start concatenation")
                }
                return
            }
            process.waitUntilExit()
            try? FileManager.default.removeItem(at: listFile)

            DispatchQueue.main.async {
                self.processes.removeValue(forKey: item.id)
                if process.terminationStatus == 0 {
                    item.outputPath = URL(fileURLWithPath: outputPath)
                    item.status = .completed
                } else {
                    item.status = .failed("Concatenation failed. Ensure all files have matching codecs and container formats.")
                }
            }
        }
    }

    // MARK: - Helpers

    private static func probeDuration(filePath: String, ffprobePath: String, env: [String: String]) -> Double {
        guard FileManager.default.fileExists(atPath: ffprobePath) else { return 0 }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffprobePath)
        p.arguments = ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", filePath]
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Double(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// Cached clean environment — built once and reused across all process launches.
    /// Using nonisolated(unsafe) static to avoid @Observable macro conflicts with lazy.
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
