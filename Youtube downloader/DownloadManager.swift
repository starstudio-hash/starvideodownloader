//
//  DownloadManager.swift
//  Youtube downloader
//

import Foundation
import AppKit
import UserNotifications
import ServiceManagement

@Observable
class DownloadManager {

    // MARK: - Settings (delegated to SettingsManager)

    let settings: SettingsManager
    var licenseManager: LicenseManager?

    var items: [DownloadItem] = []

    // History manager for recording completed downloads
    let historyManager = HistoryManager()

    // Conversion manager (persisted across tab switches)
    let conversionManager = ConversionManager()

    // Repair manager (persisted across tab switches)
    let repairManager = RepairManager()

    private var activeDownloadCount = 0
    private var waitingItems: [DownloadItem] = []

    private var processes: [UUID: Process] = [:]

    // Live bandwidth history (bytes/sec samples, last 60 at 1/sec)
    var bandwidthHistory: [Double] = []
    private var bandwidthTimer: Timer?

    // Cached yt-dlp path so we don't hit FileManager on every access
    private var _cachedYtdlpPath: String? = nil

    // Installation state
    var isInstallingYtdlp: Bool = false
    var isInstallingFfmpeg: Bool = false
    var installProgress: String = ""
    var backendHealthIssues: [BackendHealthIssue] = []
    var lastHealthCheck: Date? = nil

    private var queueSaveWork: DispatchWorkItem?
    private static let queueSaveQueue = DispatchQueue(label: "com.starvideodownloader.queue-save", qos: .utility)

    init(settings: SettingsManager, licenseManager: LicenseManager? = nil) {
        self.settings = settings
        self.licenseManager = licenseManager
        restorePersistedQueue()
    }

    // MARK: - App bin directory

    /// Directory for bundled binaries: ~/Library/Application Support/StarVideoDownloader/bin
    static let appBinDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("StarVideoDownloader/bin")
    }()

    private static let appYtdlpPath: String = {
        appBinDirectory.appendingPathComponent("yt-dlp").path
    }()

    private static let appFfmpegPath: String = {
        appBinDirectory.appendingPathComponent("ffmpeg").path
    }()

    private static let queueStateFileURL: URL = {
        appSupportDirectory().appendingPathComponent("queue-state.json")
    }()

    // MARK: - yt-dlp path

    var ytdlpPath: String {
        if let cached = _cachedYtdlpPath { return cached }
        let candidates = [
            Self.appYtdlpPath,
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        let found = candidates.first { FileManager.default.fileExists(atPath: $0) } ?? Self.appYtdlpPath
        _cachedYtdlpPath = found
        return found
    }

    var isYtdlpInstalled: Bool {
        FileManager.default.fileExists(atPath: ytdlpPath)
    }

    /// Clears cached path so next access re-scans
    func invalidatePathCache() {
        _cachedYtdlpPath = nil
        conversionManager.invalidateFfmpegPathCache()
        repairManager.invalidatePathCache()
    }

    func performStartupChecks() {
        InternalRegressionChecks.run()
        invalidatePathCache()
        refreshBackendHealth(checkVersions: true)
        setupScheduler()
        updateDockBadge()
        if !waitingItems.isEmpty {
            startNextWaiting()
        }
    }

    func refreshBackendHealth(checkVersions: Bool = false) {
        var issues: [BackendHealthIssue] = []

        if !isYtdlpInstalled {
            issues.append(
                BackendHealthIssue(
                    severity: .error,
                    title: "yt-dlp missing",
                    message: "Downloads will not start until yt-dlp is installed."
                )
            )
        } else if checkVersions && ytdlpCurrentVersion.isEmpty && !ytdlpVersionChecking {
            checkYtdlpVersion()
        }

        if !conversionManager.isFfmpegInstalled {
            issues.append(
                BackendHealthIssue(
                    severity: .warning,
                    title: "ffmpeg missing",
                    message: "Conversion, repair, and Mac-compatible remuxing are unavailable until ffmpeg is installed."
                )
            )
        }

        var isDirectory: ObjCBool = false
        let outputPath = settings.outputDirectory.path
        if !FileManager.default.fileExists(atPath: outputPath, isDirectory: &isDirectory) || !isDirectory.boolValue {
            issues.append(
                BackendHealthIssue(
                    severity: .error,
                    title: "Output folder missing",
                    message: "Choose a valid output folder before starting downloads."
                )
            )
        } else if !FileManager.default.isWritableFile(atPath: outputPath) {
            issues.append(
                BackendHealthIssue(
                    severity: .error,
                    title: "Output folder not writable",
                    message: "The current output folder does not allow writes."
                )
            )
        }

        if !settings.cookiesFilePath.isEmpty && !FileManager.default.fileExists(atPath: settings.cookiesFilePath) {
            issues.append(
                BackendHealthIssue(
                    severity: .warning,
                    title: "Cookies file missing",
                    message: "The configured cookies.txt file could not be found."
                )
            )
        }

        if settings.postDownloadAction == "script", !settings.postDownloadScript.isEmpty {
            let firstToken = settings.postDownloadScript.split(separator: " ").first.map(String.init) ?? ""
            if !firstToken.isEmpty, firstToken.hasPrefix("/"), !FileManager.default.fileExists(atPath: firstToken) {
                issues.append(
                    BackendHealthIssue(
                        severity: .warning,
                        title: "Script path missing",
                        message: "The post-download script path does not exist."
                    )
                )
            }
        }

        backendHealthIssues = issues
        lastHealthCheck = Date()
    }

    var backendHealthSummary: String? {
        backendHealthIssues.first?.message
    }

    var hasBackendErrors: Bool {
        backendHealthIssues.contains { $0.severity == .error }
    }

    private func scheduleQueuePersistence() {
        queueSaveWork?.cancel()
        let snapshot = PersistedDownloadQueue(savedAt: Date(), items: items.map(PersistedDownloadItem.init(item:)))
        let work = DispatchWorkItem {
            Self.queueSaveQueue.async {
                if snapshot.items.isEmpty {
                    try? FileManager.default.removeItem(at: Self.queueStateFileURL)
                    return
                }
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let data = try? encoder.encode(snapshot) {
                    try? data.write(to: Self.queueStateFileURL, options: .atomic)
                }
            }
        }
        queueSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: work)
    }

    private func restorePersistedQueue() {
        guard let data = try? Data(contentsOf: Self.queueStateFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(PersistedDownloadQueue.self, from: data) else { return }

        let restoredItems = snapshot.items.map { $0.makeDownloadItem() }
        items = restoredItems
        waitingItems = restoredItems.filter {
            if case .waiting = $0.status { return true }
            return false
        }
    }

    // MARK: - One-click install

    /// Downloads yt-dlp standalone binary from GitHub releases into the app's bin directory.
    func installYtdlp() {
        guard !isInstallingYtdlp else { return }
        isInstallingYtdlp = true
        installProgress = "Preparing…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                // Create bin directory
                let binDir = Self.appBinDirectory
                try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

                // Determine correct binary name for architecture
                let binaryName: String
                #if arch(arm64)
                binaryName = "yt-dlp_macos"
                #else
                binaryName = "yt-dlp_macos_legacy"
                #endif

                let downloadURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/\(binaryName)")!
                let destPath = binDir.appendingPathComponent("yt-dlp")

                DispatchQueue.main.async { self.installProgress = "Downloading yt-dlp…" }

                // Download the binary
                let semaphore = DispatchSemaphore(value: 0)
                var downloadError: Error?
                var downloadedData: Data?

                let task = URLSession.shared.dataTask(with: downloadURL) { data, response, error in
                    if let error {
                        downloadError = error
                    } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        downloadError = NSError(domain: "Install", code: httpResponse.statusCode,
                                                userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(httpResponse.statusCode))"])
                    } else {
                        downloadedData = data
                    }
                    semaphore.signal()
                }
                task.resume()
                semaphore.wait()

                if let error = downloadError { throw error }
                guard let data = downloadedData, data.count > 1000 else {
                    throw NSError(domain: "Install", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Downloaded file is too small or empty"])
                }

                DispatchQueue.main.async { self.installProgress = "Installing…" }

                // Write binary
                try data.write(to: destPath)

                // Make executable
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath.path)

                DispatchQueue.main.async {
                    self.invalidatePathCache()
                    self.isInstallingYtdlp = false
                    self.installProgress = ""
                    self.checkYtdlpVersion()
                    self.refreshBackendHealth(checkVersions: false)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isInstallingYtdlp = false
                    self.installProgress = "Failed: \(error.localizedDescription)"
                    self.refreshBackendHealth(checkVersions: false)
                }
            }
        }
    }

    /// Downloads a static ffmpeg binary into the app's bin directory.
    func installFfmpeg() {
        guard !isInstallingFfmpeg else { return }
        isInstallingFfmpeg = true
        installProgress = "Preparing…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let binDir = Self.appBinDirectory
                try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

                // Use yt-dlp's recommended ffmpeg builds from yt-dlp/FFmpeg-Builds
                let archSuffix: String
                #if arch(arm64)
                archSuffix = "arm64"
                #else
                archSuffix = "64"
                #endif

                let downloadURL = URL(string: "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-darwin\(archSuffix)-gpl.tar.xz")!

                DispatchQueue.main.async { self.installProgress = "Downloading ffmpeg…" }

                let semaphore = DispatchSemaphore(value: 0)
                var downloadError: Error?
                var tempFileURL: URL?

                // Download to temp file (ffmpeg is large)
                let tempDir = FileManager.default.temporaryDirectory
                let tempArchive = tempDir.appendingPathComponent("ffmpeg-download.tar.xz")

                let task = URLSession.shared.downloadTask(with: downloadURL) { url, response, error in
                    if let error {
                        downloadError = error
                    } else if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                        downloadError = NSError(domain: "Install", code: httpResponse.statusCode,
                                                userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(httpResponse.statusCode))"])
                    } else if let url {
                        do {
                            if FileManager.default.fileExists(atPath: tempArchive.path) {
                                try FileManager.default.removeItem(at: tempArchive)
                            }
                            try FileManager.default.moveItem(at: url, to: tempArchive)
                            tempFileURL = tempArchive
                        } catch {
                            downloadError = error
                        }
                    }
                    semaphore.signal()
                }
                task.resume()
                semaphore.wait()

                if let error = downloadError { throw error }
                guard let archivePath = tempFileURL else {
                    throw NSError(domain: "Install", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Download produced no file"])
                }

                DispatchQueue.main.async { self.installProgress = "Extracting ffmpeg…" }

                // Extract using tar
                let extractDir = tempDir.appendingPathComponent("ffmpeg-extract")
                if FileManager.default.fileExists(atPath: extractDir.path) {
                    try FileManager.default.removeItem(at: extractDir)
                }
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                process.arguments = ["xf", archivePath.path, "-C", extractDir.path]
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    throw NSError(domain: "Install", code: Int(process.terminationStatus),
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to extract ffmpeg archive"])
                }

                DispatchQueue.main.async { self.installProgress = "Installing…" }

                // Find the ffmpeg binary in the extracted directory
                let enumerator = FileManager.default.enumerator(at: extractDir, includingPropertiesForKeys: nil)
                var ffmpegBinary: URL?
                var ffprobeBinary: URL?
                while let fileURL = enumerator?.nextObject() as? URL {
                    if fileURL.lastPathComponent == "ffmpeg" && fileURL.pathComponents.contains("bin") {
                        ffmpegBinary = fileURL
                    }
                    if fileURL.lastPathComponent == "ffprobe" && fileURL.pathComponents.contains("bin") {
                        ffprobeBinary = fileURL
                    }
                }

                guard let sourceBinary = ffmpegBinary else {
                    throw NSError(domain: "Install", code: -1,
                                  userInfo: [NSLocalizedDescriptionKey: "Could not find ffmpeg binary in archive"])
                }

                let destFfmpeg = binDir.appendingPathComponent("ffmpeg")
                let destFfprobe = binDir.appendingPathComponent("ffprobe")

                // Remove existing if present
                if FileManager.default.fileExists(atPath: destFfmpeg.path) {
                    try FileManager.default.removeItem(at: destFfmpeg)
                }
                if FileManager.default.fileExists(atPath: destFfprobe.path) {
                    try FileManager.default.removeItem(at: destFfprobe)
                }

                try FileManager.default.copyItem(at: sourceBinary, to: destFfmpeg)
                if let probeSource = ffprobeBinary {
                    try FileManager.default.copyItem(at: probeSource, to: destFfprobe)
                }

                // Make executable
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destFfmpeg.path)
                if FileManager.default.fileExists(atPath: destFfprobe.path) {
                    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destFfprobe.path)
                }

                // Cleanup temp files
                try? FileManager.default.removeItem(at: archivePath)
                try? FileManager.default.removeItem(at: extractDir)

                DispatchQueue.main.async {
                    self.invalidatePathCache()
                    self.isInstallingFfmpeg = false
                    self.installProgress = ""
                    self.refreshBackendHealth(checkVersions: false)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isInstallingFfmpeg = false
                    self.installProgress = "Failed: \(error.localizedDescription)"
                    self.refreshBackendHealth(checkVersions: false)
                }
            }
        }
    }

    // MARK: - yt-dlp Version & Update

    var ytdlpCurrentVersion: String = ""
    var ytdlpLatestVersion: String = ""
    var ytdlpUpdateAvailable: Bool = false
    var ytdlpVersionChecking: Bool = false
    var ytdlpUpdating: Bool = false

    func checkYtdlpVersion() {
        guard isYtdlpInstalled else { return }
        ytdlpVersionChecking = true
        let ytdlp = ytdlpPath
        let env = buildCleanEnvironment()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            // Get current version
            let currentVersion = Self.runSimpleCommand(executablePath: ytdlp, arguments: ["--version"], env: env)

            // Get latest version from GitHub API
            var latestVersion = ""
            if let url = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest") {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                let semaphore = DispatchSemaphore(value: 0)
                URLSession.shared.dataTask(with: request) { data, _, _ in
                    if let data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let tagName = json["tag_name"] as? String {
                        latestVersion = tagName
                    }
                    semaphore.signal()
                }.resume()
                semaphore.wait()
            }

            DispatchQueue.main.async {
                self.ytdlpCurrentVersion = currentVersion
                self.ytdlpLatestVersion = latestVersion
                self.ytdlpUpdateAvailable = !latestVersion.isEmpty && !currentVersion.isEmpty && latestVersion != currentVersion
                self.ytdlpVersionChecking = false
            }
        }
    }

    func updateYtdlp() {
        guard isYtdlpInstalled else { return }
        ytdlpUpdating = true
        let ytdlp = ytdlpPath
        let env = buildCleanEnvironment()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Try yt-dlp -U first
            let result = Self.runSimpleCommand(executablePath: ytdlp, arguments: ["-U"], env: env)
            let success = result.contains("Updated") || result.contains("up to date") || result.contains("already")

            DispatchQueue.main.async {
                self.ytdlpUpdating = false
                if success {
                    // Re-check version after update
                    self.checkYtdlpVersion()
                }
            }
        }
    }

    private static func runSimpleCommand(executablePath: String, arguments: [String], env: [String: String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return "" }
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Duplicate detection

    /// Returns true if a download for this URL is already queued or in progress.
    func isDuplicate(url: String) -> Bool {
        items.contains { item in
            item.url == url && !matchesTerminalState(item.status)
        }
    }

    func duplicateMessage(for url: String) -> String? {
        if items.contains(where: { $0.url == url && !matchesTerminalState($0.status) }) {
            return "This URL is already in your queue."
        }
        if historyManager.entries.contains(where: { $0.url == url }) {
            return "This URL already exists in your download history."
        }
        return nil
    }

    private func matchesTerminalState(_ status: DownloadStatus) -> Bool {
        switch status {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }

    // MARK: - Public API

    @discardableResult
    func addDownload(url: String, quality: VideoQuality? = nil, format: OutputFormat? = nil,
                     subtitles: Bool? = nil, playlistDownload: Bool = false,
                     scheduledStartDate: Date? = nil) -> Bool {
        // Enforce license: check daily download limit for free users
        if let lm = licenseManager, !lm.hasFullAccess, !lm.canDownload {
            return false
        }

        // Enforce license: clamp quality to allowed tier
        var effectiveQuality = quality ?? settings.defaultQuality
        if let lm = licenseManager, !lm.hasFullAccess {
            if !lm.allowedQualities.contains(effectiveQuality) {
                effectiveQuality = .best1080
            }
        }

        let item = DownloadItem(
            url: url,
            quality: effectiveQuality,
            format: format ?? settings.defaultFormat,
            subtitles: subtitles ?? settings.downloadSubtitlesByDefault,
            playlistDownload: playlistDownload,
            scheduledStartDate: scheduledStartDate
        )
        items.append(item)
        prefetchMetadataIfNeeded(for: item)
        enqueueOrStart(item)
        scheduleQueuePersistence()
        setupScheduler()
        if let lm = licenseManager, !lm.hasFullAccess {
            lm.recordDownload()
        }
        return true
    }

    /// Fetches all video URLs from a playlist, then enqueues each as an individual download.
    func addPlaylistDownload(url: String, quality: VideoQuality? = nil, format: OutputFormat? = nil,
                             subtitles: Bool? = nil) {
        // Enforce license: playlists require full access
        if let lm = licenseManager, !lm.hasFullAccess {
            return
        }

        let q = quality ?? settings.defaultQuality
        let fmt = format ?? settings.defaultFormat
        let subs = subtitles ?? settings.downloadSubtitlesByDefault
        // Add a placeholder item to show something immediately
        let placeholder = DownloadItem(url: url, quality: q, format: fmt, subtitles: subs)
        placeholder.title = "Fetching playlist…"
        placeholder.status = .fetchingInfo
        items.append(placeholder)
        scheduleQueuePersistence()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.fetchPlaylistEntries(url: url)

            DispatchQueue.main.async {
                // Remove the placeholder
                self.items.removeAll { $0.id == placeholder.id }

                guard let result else {
                    placeholder.title = "Playlist fetch failed"
                    placeholder.status = .failed("Could not fetch playlist. Check the URL and try again.")
                    self.items.append(placeholder)
                    self.scheduleQueuePersistence()
                    return
                }

                guard !result.entries.isEmpty else {
                    // Put placeholder back with error message so user sees something
                    placeholder.title = "No videos found in playlist"
                    placeholder.status = .failed("The playlist appears to be empty or private.")
                    self.items.append(placeholder)
                    self.scheduleQueuePersistence()
                    return
                }

                // Enqueue each video as its own DownloadItem
                for entry in result.entries {
                    let item = DownloadItem(
                        url: entry.url,
                        quality: q,
                        format: fmt,
                        subtitles: subs,
                        playlistDownload: false,
                        playlistTitle: result.title,
                        playlistIndex: entry.index
                    )
                    item.title = entry.title
                    self.items.append(item)
                    self.prefetchMetadataIfNeeded(for: item)
                    self.enqueueOrStart(item)
                }
                self.scheduleQueuePersistence()
                self.setupScheduler()
            }
        }
    }

    func inspectPlaylist(url: String, completion: @escaping (Result<URLInspectionResult, URLInspectionError>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            guard let result = self.fetchPlaylistEntries(url: url) else {
                DispatchQueue.main.async {
                    completion(.failure(.message("Could not inspect that playlist.")))
                }
                return
            }

            let inspection = URLInspectionResult(
                title: result.title,
                channel: nil,
                durationText: nil,
                thumbnailURL: nil,
                isLiveStream: false,
                isPlaylist: true,
                playlistTitle: result.title,
                playlistCount: result.entries.count
            )
            DispatchQueue.main.async {
                completion(.success(inspection))
            }
        }
    }

    func cancelDownload(_ item: DownloadItem) {
        // Only decrement if this item was actively running (not just waiting)
        let wasRunning: Bool
        switch item.status {
        case .downloading, .processing, .fetchingInfo:
            wasRunning = true
        default:
            wasRunning = false
        }
        processes[item.id]?.terminate()
        processes[item.id] = nil
        item.status = .cancelled
        waitingItems.removeAll { $0.id == item.id }
        if wasRunning && activeDownloadCount > 0 {
            activeDownloadCount -= 1
        }
        startNextWaiting()
        scheduleQueuePersistence()
        setupScheduler()
    }

    func pauseDownload(_ item: DownloadItem) {
        guard let process = processes[item.id], process.isRunning else { return }
        process.suspend()
        if case .downloading(let progress, _, _) = item.status {
            item.status = .paused(progress: progress)
            scheduleQueuePersistence()
        }
    }

    func resumeDownload(_ item: DownloadItem) {
        guard let process = processes[item.id] else { return }
        process.resume()
        if case .paused(let progress) = item.status {
            item.status = .downloading(progress: progress, speed: "—", eta: "—")
            scheduleQueuePersistence()
        }
    }

    func pauseAll() {
        for item in items {
            if case .downloading = item.status {
                pauseDownload(item)
            }
        }
    }

    func resumeAll() {
        for item in items {
            if case .paused = item.status {
                resumeDownload(item)
            }
        }
    }

    /// Aggregate bandwidth string from all active downloads
    var totalBandwidth: String? {
        var totalBytes: Double = 0
        var count = 0
        for item in items {
            if case .downloading(_, let speed, _) = item.status {
                totalBytes += Self.parseSpeed(speed)
                count += 1
            }
        }
        guard count > 1 else { return nil }  // Only show when multiple downloads active
        return Self.formatSpeed(totalBytes)
    }

    /// Start sampling bandwidth at 1Hz for live graph
    func startBandwidthSampling() {
        guard bandwidthTimer == nil else { return }
        bandwidthTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            var total: Double = 0
            for item in self.items {
                if case .downloading(_, let speed, _) = item.status {
                    total += Self.parseSpeed(speed)
                }
            }
            self.bandwidthHistory.append(total)
            if self.bandwidthHistory.count > 60 {
                self.bandwidthHistory.removeFirst(self.bandwidthHistory.count - 60)
            }
        }
    }

    func stopBandwidthSampling() {
        bandwidthTimer?.invalidate()
        bandwidthTimer = nil
    }

    private static func parseSpeed(_ speed: String) -> Double {
        let trimmed = speed.trimmingCharacters(in: .whitespaces)
        let multipliers: [(String, Double)] = [
            ("GiB/s", 1_073_741_824), ("GB/s", 1_000_000_000),
            ("MiB/s", 1_048_576), ("MB/s", 1_000_000),
            ("KiB/s", 1_024), ("KB/s", 1_000),
            ("B/s", 1)
        ]
        for (suffix, mult) in multipliers {
            if trimmed.hasSuffix(suffix),
               let val = Double(trimmed.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)) {
                return val * mult
            }
        }
        return 0
    }

    private static func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 {
            return String(format: "%.1f MiB/s", bytesPerSec / 1_048_576)
        } else if bytesPerSec >= 1_024 {
            return String(format: "%.0f KiB/s", bytesPerSec / 1_024)
        }
        return String(format: "%.0f B/s", bytesPerSec)
    }

    var hasPausedItems: Bool {
        items.contains { if case .paused = $0.status { return true }; return false }
    }

    var hasActiveDownloads: Bool {
        items.contains { if case .downloading = $0.status { return true }; return false }
    }

    func removeItem(_ item: DownloadItem) {
        cancelDownload(item)
        items.removeAll { $0.id == item.id }
        scheduleQueuePersistence()
        setupScheduler()
    }

    func moveItem(from sourceID: UUID, to targetID: UUID) {
        guard sourceID != targetID,
              let sourceIndex = items.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = items.firstIndex(where: { $0.id == targetID })
        else { return }
        let item = items.remove(at: sourceIndex)
        items.insert(item, at: targetIndex)
        rebuildWaitingQueue()
        scheduleQueuePersistence()
    }

    func retryDownload(_ item: DownloadItem) {
        item.status = .waiting
        if item.title.isEmpty || item.title == item.url {
            item.title = item.url
        }
        item.channelName = ""
        item.duration = ""
        item.thumbnail = nil
        item.outputPath = nil
        item.integrityWarning = nil
        prefetchMetadataIfNeeded(for: item)
        enqueueOrStart(item)
        scheduleQueuePersistence()
        setupScheduler()
    }

    func retryFailedDownloads() {
        for item in items {
            if case .failed = item.status {
                retryDownload(item)
            }
        }
    }

    func removeFailedDownloads() {
        items.removeAll {
            if case .failed = $0.status { return true }
            return false
        }
        rebuildWaitingQueue()
        scheduleQueuePersistence()
    }

    func clearCompleted() {
        items.removeAll {
            if case .completed = $0.status { return true }
            if case .cancelled = $0.status { return true }
            return false
        }
        rebuildWaitingQueue()
        scheduleQueuePersistence()
    }

    func clearAllDownloads() {
        for item in items where item.status.isActive {
            cancelDownload(item)
        }
        items.removeAll()
        waitingItems.removeAll()
        scheduleQueuePersistence()
        setupScheduler()
    }

    func openInFinder(_ item: DownloadItem) {
        if let path = item.outputPath, FileManager.default.fileExists(atPath: path.path) {
            NSWorkspace.shared.activateFileViewerSelecting([path])
        } else {
            NSWorkspace.shared.open(settings.outputDirectory)
        }
    }

    func updateScheduledStart(for item: DownloadItem, date: Date?) {
        item.scheduledStartDate = date
        if case .failed(let message) = item.status, message.contains("Interrupted by a previous app session") {
            item.status = .waiting
        }
        if case .waiting = item.status {
            waitingItems.removeAll { $0.id == item.id }
            waitingItems.append(item)
        }
        scheduleQueuePersistence()
        setupScheduler()
        startNextWaiting()
    }

    func failureRecoverySuggestion(for item: DownloadItem) -> String? {
        guard case .failed(let message) = item.status else { return nil }
        let lower = message.lowercased()

        if lower.contains("private") || lower.contains("login") || lower.contains("sign in") {
            return "Try browser cookies or a cookies.txt file in Settings."
        }
        if lower.contains("rate") || lower.contains("too many requests") || lower.contains("http error 429") {
            return "Reduce speed, enable sleep intervals, or try again later."
        }
        if lower.contains("ffmpeg") {
            return "Install ffmpeg from the app before retrying."
        }
        if lower.contains("yt-dlp not found") {
            return "Install yt-dlp from the Downloads tab or Settings."
        }
        if lower.contains("geo") || lower.contains("region") {
            return "Try Geo Bypass in Advanced Settings."
        }
        if lower.contains("interrupted by a previous app session") {
            return "Retry will usually resume from the partial file if it still exists."
        }
        return "Retry with different quality, format, or authentication settings."
    }

    private struct PlaylistFetchResult {
        var title: String
        var entries: [(url: String, title: String, index: Int)]
    }

    private func fetchPlaylistEntries(url: String) -> PlaylistFetchResult? {
        guard isYtdlpInstalled else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = ["--flat-playlist", "--dump-single-json", "--no-warnings", url]
        process.environment = buildCleanEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            return nil
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let playlistTitle = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = json["entries"] as? [[String: Any]] ?? []
        let normalizedEntries = entries.enumerated().compactMap { offset, entry -> (String, String, Int)? in
            let title = (entry["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let index = entry["playlist_index"] as? Int ?? (offset + 1)

            if let webpageURL = entry["url"] as? String, webpageURL.starts(with: "http") {
                return (webpageURL, title ?? webpageURL, index)
            }

            let videoID = entry["id"] as? String ?? ""
            guard !videoID.isEmpty else { return nil }
            let extractor = (entry["extractor_key"] as? String ?? "").lowercased()
            let resolvedURL: String
            switch extractor {
            case "vimeo":
                resolvedURL = "https://vimeo.com/\(videoID)"
            case "tiktok":
                resolvedURL = "https://www.tiktok.com/@video/\(videoID)"
            default:
                resolvedURL = "https://www.youtube.com/watch?v=\(videoID)"
            }
            return (resolvedURL, title ?? videoID, index)
        }

        return PlaylistFetchResult(title: playlistTitle?.isEmpty == false ? playlistTitle! : "Playlist", entries: normalizedEntries)
    }

    private func prefetchMetadataIfNeeded(for item: DownloadItem) {
        guard isYtdlpInstalled else { return }
        guard item.playlistTitle == nil else { return }

        let ytdlp = ytdlpPath
        let env = buildCleanEnvironment()
        let url = item.url

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytdlp)
            process.arguments = ["--dump-single-json", "--skip-download", "--no-playlist", "--no-warnings", url]
            process.environment = env

            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                return
            }
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return }
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            let title = (json["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let channel = (json["channel"] as? String ?? json["uploader"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let duration = (json["duration"] as? Int).map(self.formatDuration)
            let thumbnail = (json["thumbnail"] as? String).flatMap(URL.init(string:))
            let isLive = (json["is_live"] as? Bool) ?? false

            DispatchQueue.main.async {
                guard self.items.contains(where: { $0.id == item.id }) else { return }
                if item.title == item.url, let title, !title.isEmpty {
                    item.title = title
                }
                if item.channelName.isEmpty, !channel.isEmpty {
                    item.channelName = channel
                }
                if item.duration.isEmpty, let duration {
                    item.duration = duration
                }
                if item.thumbnail == nil {
                    item.thumbnail = thumbnail
                }
                if isLive {
                    item.isLiveStream = true
                }
                self.scheduleQueuePersistence()
            }
        }
    }

    // MARK: - Concurrency Queue

    /// Effective concurrent limit respecting both user settings and license tier
    private var effectiveMaxConcurrent: Int {
        let settingsMax = settings.maxConcurrentDownloads
        if let lm = licenseManager, !lm.hasFullAccess {
            return min(settingsMax, LicenseManager.freeMaxConcurrentDownloads)
        }
        // Pro users: 0 means unlimited (use a high practical cap)
        if settingsMax == 0 { return 99 }
        return settingsMax
    }

    private func enqueueOrStart(_ item: DownloadItem) {
        if !itemCanStartNow(item) {
            item.status = .waiting
            waitingItems.removeAll { $0.id == item.id }
            waitingItems.append(item)
            scheduleQueuePersistence()
            setupScheduler()
            return
        }
        if activeDownloadCount < effectiveMaxConcurrent {
            activeDownloadCount += 1
            startDownloadInBackground(item)
        } else {
            item.status = .waiting
            waitingItems.removeAll { $0.id == item.id }
            waitingItems.append(item)
        }
        scheduleQueuePersistence()
        setupScheduler()
    }

    private func startNextWaiting() {
        rebuildWaitingQueue()
        while activeDownloadCount < effectiveMaxConcurrent {
            guard let nextIndex = waitingItems.firstIndex(where: { itemCanStartNow($0) }) else { break }
            let next = waitingItems.remove(at: nextIndex)
            // Only start if the item is still in our list (not removed)
            guard items.contains(where: { $0.id == next.id }) else { continue }
            activeDownloadCount += 1
            startDownloadInBackground(next)
        }
        scheduleQueuePersistence()
    }

    private func rebuildWaitingQueue() {
        let waitingIDs = Set(
            items.compactMap { item in
                if case .waiting = item.status { return item.id }
                return nil
            }
        )
        waitingItems = items.filter { waitingIDs.contains($0.id) }
    }

    private func itemCanStartNow(_ item: DownloadItem, now: Date = Date()) -> Bool {
        if let scheduledStart = item.scheduledStartDate, scheduledStart > now {
            return false
        }

        guard settings.scheduledDownloadEnabled else { return true }
        let calendar = Calendar.current
        guard let scheduledToday = calendar.date(
            bySettingHour: calendar.component(.hour, from: settings.scheduledDownloadTime),
            minute: calendar.component(.minute, from: settings.scheduledDownloadTime),
            second: 0,
            of: now
        ) else {
            return true
        }
        return now >= scheduledToday
    }

    // MARK: - Background Download (no async/await — plain GCD to avoid actor issues)

    private func startDownloadInBackground(_ item: DownloadItem) {
        guard isYtdlpInstalled else {
            item.status = .failed("yt-dlp not found. Install it from the Downloads tab.")
            if activeDownloadCount > 0 { activeDownloadCount -= 1 }
            startNextWaiting()
            refreshBackendHealth()
            scheduleQueuePersistence()
            return
        }

        item.status = .downloading(progress: 0, speed: "—", eta: "—")
        scheduleQueuePersistence()
        updateDockBadge()

        // Snapshot all item properties we need before leaving main thread
        let url = item.url
        let fmt = item.format
        let quality = item.quality
        let subtitles = item.subtitles
        let isPlaylist = item.playlistDownload
        let outDir = settings.outputDirectory
        let ytdlp = ytdlpPath
        let macCompat = settings.macCompatibleEncoding
        let encQuality = settings.encodingQuality
        let vidCodec = settings.selectedVideoCodec
        let audCodec = settings.selectedAudioCodec
        // Snapshot yt-dlp flag settings
        let cookies = settings.cookiesFromBrowser
        let rateLimit = settings.rateLimitEnabled ? settings.rateLimitSpeed : nil
        let archive = settings.useDownloadArchive
        let sponsor = settings.sponsorBlockEnabled ? settings.sponsorBlockMode : nil
        let embedThumb = settings.embedThumbnail
        let embedMeta = settings.embedMetadata
        let embedChap = settings.embedChapters
        let splitChap = settings.splitChapters
        let geoBP = settings.geoBypass
        let geoBPCountry = settings.geoBypassCountry
        let concFrags = settings.concurrentFragments
        let plItems = settings.playlistItemsFilter
        let mFilter = settings.matchFilter
        let fnTemplate = settings.filenameTemplate
        let autoOrg = settings.autoOrganize
        let orgBy = settings.organizeBy
        let liveFromStart = settings.liveFromStart
        let waitForVideo = settings.waitForVideo
        let sleepInterval = settings.sleepIntervalEnabled ? (min: settings.sleepIntervalMin, max: settings.sleepIntervalMax) : nil as (min: Int, max: Int)?
        let fmtSort = settings.formatSortString
        let embedSubs = settings.embedSubtitles
        let fileConflict = settings.fileConflictBehavior
        let cookiesFile = settings.cookiesFilePath
        let convertThumbs = settings.convertThumbnailsFormat

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            self.runYtdlp(
                item: item,
                url: url,
                format: fmt,
                quality: quality,
                subtitles: subtitles,
                isPlaylist: isPlaylist,
                outputDirectory: outDir,
                ytdlpPath: ytdlp,
                macCompatible: macCompat,
                encodingQuality: encQuality,
                videoCodec: vidCodec,
                audioCodec: audCodec,
                cookiesBrowser: cookies,
                rateLimit: rateLimit,
                useArchive: archive,
                sponsorBlock: sponsor,
                embedThumbnail: embedThumb,
                embedMetadata: embedMeta,
                embedChapters: embedChap,
                splitChapters: splitChap,
                geoBypass: geoBP,
                geoBypassCountry: geoBPCountry,
                concurrentFragments: concFrags,
                playlistItems: plItems,
                matchFilter: mFilter,
                filenameTemplate: fnTemplate,
                autoOrganize: autoOrg,
                organizeBy: orgBy,
                liveFromStart: liveFromStart,
                waitForVideo: waitForVideo,
                sleepInterval: sleepInterval,
                formatSort: fmtSort,
                embedSubtitles: embedSubs,
                fileConflict: fileConflict,
                cookiesFile: cookiesFile,
                convertThumbnails: convertThumbs
            )
            // Decrement active count and start next queued download
            DispatchQueue.main.async {
                if self.activeDownloadCount > 0 { self.activeDownloadCount -= 1 }
                self.startNextWaiting()
            }
        }
    }

    private func runYtdlp(
        item: DownloadItem,
        url: String,
        format: OutputFormat,
        quality: VideoQuality,
        subtitles: Bool,
        isPlaylist: Bool,
        outputDirectory: URL,
        ytdlpPath: String,
        macCompatible: Bool,
        encodingQuality: EncodingQuality,
        videoCodec: VideoCodec = .h264,
        audioCodec: AudioCodec = .aac,
        cookiesBrowser: String = "none",
        rateLimit: String? = nil,
        useArchive: Bool = false,
        sponsorBlock: String? = nil,
        embedThumbnail: Bool = false,
        embedMetadata: Bool = false,
        embedChapters: Bool = false,
        splitChapters: Bool = false,
        geoBypass: Bool = false,
        geoBypassCountry: String = "",
        concurrentFragments: Int = 1,
        playlistItems: String = "",
        matchFilter: String = "",
        filenameTemplate: String = "%(title)s.%(ext)s",
        autoOrganize: Bool = false,
        organizeBy: String = "none",
        liveFromStart: Bool = false,
        waitForVideo: Bool = false,
        sleepInterval: (min: Int, max: Int)? = nil,
        formatSort: String = "",
        embedSubtitles: Bool = false,
        fileConflict: String = "rename",
        cookiesFile: String = "",
        convertThumbnails: String = ""
    ) {
        var args: [String] = []

        let isAudioJob = format == .mp3 || format == .m4a || quality.isAudioOnly
        if isAudioJob {
            let audioFmt = format == .m4a ? "m4a" : "mp3"
            args += ["-x", "--audio-format", audioFmt, "--audio-quality", "0"]
        } else {
            // Always download and merge into mkv first (lossless, no postprocessing by yt-dlp).
            // If macCompatible, we run ffmpeg ourselves afterward to convert to H.264+AAC MP4.
            let mergeExt = macCompatible ? "mkv" : format.rawValue.lowercased()
            args += ["-f", quality.ytdlpFormat, "--merge-output-format", mergeExt]
        }

        if subtitles {
            args += ["--write-subs", "--write-auto-subs", "--sub-langs", "all"]
        }

        if !isPlaylist {
            args += ["--no-playlist"]
        }

        // yt-dlp flags from settings
        if cookiesBrowser != "none" && !cookiesBrowser.isEmpty {
            args += ["--cookies-from-browser", cookiesBrowser]
        }
        if let rateLimit, !rateLimit.isEmpty {
            args += ["--rate-limit", rateLimit]
        }
        if useArchive {
            let archivePath = Self.appSupportDirectory().appendingPathComponent("download-archive.txt").path
            args += ["--download-archive", archivePath]
        }
        if let sponsorBlock {
            args += ["--sponsorblock-remove", sponsorBlock]
        }
        if embedThumbnail {
            args += ["--embed-thumbnail"]
        }
        if embedMetadata {
            args += ["--embed-metadata"]
        }
        if embedChapters {
            args += ["--embed-chapters"]
        }
        if splitChapters {
            args += ["--split-chapters"]
        }
        if geoBypass {
            if !geoBypassCountry.isEmpty {
                args += ["--geo-bypass-country", geoBypassCountry]
            } else {
                args += ["--geo-bypass"]
            }
        }
        if concurrentFragments > 1 {
            args += ["--concurrent-fragments", "\(concurrentFragments)"]
        }
        if !playlistItems.isEmpty {
            args += ["--playlist-items", playlistItems]
        }
        if !matchFilter.isEmpty {
            args += ["--match-filter", matchFilter]
        }
        if liveFromStart {
            args += ["--live-from-start"]
        }
        if waitForVideo {
            args += ["--wait-for-video", "30"]
        }
        if let sleepInterval {
            args += ["--sleep-interval", "\(sleepInterval.min)"]
            if sleepInterval.max > sleepInterval.min {
                args += ["--max-sleep-interval", "\(sleepInterval.max)"]
            }
        }
        if !formatSort.isEmpty {
            args += ["-S", formatSort]
        }
        if embedSubtitles {
            args += ["--embed-subs"]
        }
        // File conflict behavior
        switch fileConflict {
        case "overwrite":
            args += ["--force-overwrites"]
        case "skip":
            args += ["--no-overwrites"]
        default:
            break // "rename" is yt-dlp's default behavior
        }
        // Cookies file for site authentication
        if !cookiesFile.isEmpty {
            args += ["--cookies", cookiesFile]
        }
        // Convert embedded thumbnails format
        if embedThumbnail && !convertThumbnails.isEmpty {
            args += ["--convert-thumbnails", convertThumbnails]
        }

        let ffmpegPath = ytdlpPath.replacingOccurrences(of: "yt-dlp", with: "ffmpeg")
        let ffmpegDir = (ffmpegPath as NSString).deletingLastPathComponent
        if FileManager.default.fileExists(atPath: ffmpegPath) {
            args += ["--ffmpeg-location", ffmpegDir]
        }

        // Build output template with optional auto-organize subdirectories
        var templatePath = ""
        if autoOrganize && organizeBy != "none" {
            switch organizeBy {
            case "channel":  templatePath = "%(channel)s/"
            case "playlist": templatePath = "%(playlist_title)s/"
            case "date":     templatePath = "%(upload_date>%Y)s/%(upload_date>%m)s/"
            case "format":   templatePath = "%(ext)s/"
            default: break
            }
        }
        templatePath += filenameTemplate
        let outputTemplate = outputDirectory.appendingPathComponent(templatePath).path
        args += ["-o", outputTemplate, "--newline", "--no-colors"]
        args.append(url)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = args
        process.environment = buildCleanEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        DispatchQueue.main.async { self.processes[item.id] = process }

        var lineBuffer = ""
        var stderrBuffer = ""
        var capturedOutputPath: URL? = nil
        var lastYtdlpProgressUpdate = DispatchTime.now()

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard self != nil else { return }
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            lineBuffer += chunk
            // Guard against runaway buffer (cap at 1MB)
            if lineBuffer.count > 1_048_576 {
                lineBuffer = String(lineBuffer.suffix(65536))
            }
            var lines = lineBuffer.components(separatedBy: "\n")
            lineBuffer = lines.removeLast()

            // Batch: collect the latest progress status + any metadata updates
            var latestStatus: DownloadStatus? = nil
            var latestTitle: String? = nil
            var latestChannel: String? = nil

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let (status, outPath, title, channel, isLive) = Self.parseLine(trimmed, currentOutputPath: capturedOutputPath)
                if let outPath {
                    capturedOutputPath = outPath
                    // Set outputPath early so partial file can be previewed
                    DispatchQueue.main.async { item.outputPath = outPath }
                }
                if let status { latestStatus = status }
                if let title { latestTitle = title }
                if let channel { latestChannel = channel }
                if isLive == true {
                    DispatchQueue.main.async { item.isLiveStream = true }
                }
            }

            // Metadata updates (title, channel) are dispatched immediately — they're rare
            if latestTitle != nil || latestChannel != nil {
                let t = latestTitle, c = latestChannel
                DispatchQueue.main.async {
                    if let t, item.title == item.url { item.title = t }
                    if let c { item.channelName = c }
                }
            }

            // Progress updates are throttled to ~10/sec
            if let status = latestStatus {
                let now = DispatchTime.now()
                let isProgressLine: Bool
                if case .downloading = status { isProgressLine = true }
                else { isProgressLine = false }

                if isProgressLine && now <= lastYtdlpProgressUpdate + .milliseconds(100) {
                    // Skip this progress update — too soon
                } else {
                    if isProgressLine { lastYtdlpProgressUpdate = now }
                    DispatchQueue.main.async {
                        item.status = status
                        // Record speed for sparkline
                        if case .downloading(_, let speed, _) = status {
                            let speedBytes = Self.parseSpeed(speed)
                            if speedBytes > 0 {
                                item.speedHistory.append(speedBytes)
                                if item.speedHistory.count > 20 {
                                    item.speedHistory.removeFirst(item.speedHistory.count - 20)
                                }
                            }
                        }
                        self?.scheduleQueuePersistence()
                    }
                }
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard self != nil else { return }
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            stderrBuffer += chunk
            // Cap stderr buffer too
            if stderrBuffer.count > 524_288 {
                stderrBuffer = String(stderrBuffer.suffix(32768))
            }
        }

        do { try process.run() } catch {
            DispatchQueue.main.async {
                item.status = .failed("Could not start yt-dlp: \(error.localizedDescription)")
                self.scheduleQueuePersistence()
                self.refreshBackendHealth()
            }
            return
        }

        process.waitUntilExit()
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        // Flush remaining buffer
        let remaining = lineBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let (lastStatus, lastPath, lastTitle, lastChannel, _) = Self.parseLine(remaining, currentOutputPath: capturedOutputPath)
        if let lastPath { capturedOutputPath = lastPath }

        DispatchQueue.main.async {
            self.processes.removeValue(forKey: item.id)
            if !remaining.isEmpty {
                if let lastStatus { item.status = lastStatus }
                if let lastTitle, item.title == item.url { item.title = lastTitle }
                if let lastChannel { item.channelName = lastChannel }
            }
            self.scheduleQueuePersistence()
        }

        guard process.terminationStatus == 0 else {
            if case .cancelled = item.status { return }
            let errMsg = Self.extractUserFriendlyError(from: stderrBuffer, exitCode: process.terminationStatus)
            DispatchQueue.main.async {
                item.status = .failed(errMsg)
                self.postNotification(title: "Download Failed", body: item.title)
                self.updateDockBadge()
                self.scheduleQueuePersistence()
            }
            return
        }

        // yt-dlp finished. If macCompatible, run ffmpeg to convert to H.264+AAC MP4.
        let isVideoJob = !isAudioJob
        if isVideoJob && macCompatible {
            // Find the output file — use captured path or scan directory as fallback
            let mkvPath: URL?
            if let captured = capturedOutputPath, FileManager.default.fileExists(atPath: captured.path) {
                mkvPath = captured
            } else {
                // Fallback: find the most recently modified MKV in the output directory
                mkvPath = Self.findMostRecentFile(in: outputDirectory, extension: "mkv")
            }

            if let mkvPath {
                let outputExt = videoCodec.preferredContainer
                let outputFilePath = mkvPath.deletingPathExtension().appendingPathExtension(outputExt)
                DispatchQueue.main.async { item.status = .processing(progress: 0) }

                // Get the video duration first so we can report percentage progress.
                let ffprobePath = ffmpegPath.replacingOccurrences(of: "ffmpeg", with: "ffprobe")
                let totalSeconds = Self.probeDuration(filePath: mkvPath.path, ffprobePath: ffprobePath, env: buildCleanEnvironment())

                // Build codec arguments based on selected codecs
                let audioArgs: [String] = ["-c:a", audioCodec.ffmpegEncoder] + audioCodec.qualityArgs(quality: encodingQuality)

                var success = false

                if videoCodec == .copy {
                    // Stream copy — no re-encoding
                    success = runFfmpeg(
                        ffmpegPath: ffmpegPath,
                        input: mkvPath.path,
                        output: outputFilePath.path,
                        videoCodec: "copy",
                        codecArgs: audioArgs,
                        totalSeconds: totalSeconds,
                        item: item
                    )
                } else if let hwEncoder = videoCodec.hardwareEncoder {
                    // Try hardware encoder first
                    let hwArgs = videoCodec.hardwareQualityArgs(quality: encodingQuality) + audioArgs
                    success = runFfmpeg(
                        ffmpegPath: ffmpegPath,
                        input: mkvPath.path,
                        output: outputFilePath.path,
                        videoCodec: hwEncoder,
                        codecArgs: hwArgs,
                        totalSeconds: totalSeconds,
                        item: item
                    )
                    // Fall back to software encoder if hardware failed
                    if !success, let swEncoder = videoCodec.softwareEncoder {
                        let swArgs = videoCodec.softwareQualityArgs(quality: encodingQuality) + audioArgs
                        success = runFfmpeg(
                            ffmpegPath: ffmpegPath,
                            input: mkvPath.path,
                            output: outputFilePath.path,
                            videoCodec: swEncoder,
                            codecArgs: swArgs,
                            totalSeconds: totalSeconds,
                            item: item
                        )
                    }
                } else if let swEncoder = videoCodec.softwareEncoder {
                    // Software-only codec (e.g., VP9)
                    let swArgs = videoCodec.softwareQualityArgs(quality: encodingQuality) + audioArgs
                    success = runFfmpeg(
                        ffmpegPath: ffmpegPath,
                        input: mkvPath.path,
                        output: outputFilePath.path,
                        videoCodec: swEncoder,
                        codecArgs: swArgs,
                        totalSeconds: totalSeconds,
                        item: item
                    )
                }

                if success {
                    // Remove original MKV if output is a different file
                    if mkvPath.path != outputFilePath.path {
                        try? FileManager.default.removeItem(at: mkvPath)
                    }
                    DispatchQueue.main.async {
                        item.outputPath = outputFilePath
                        item.status = .completed
                        self.historyManager.record(item: item)
                        self.postNotification(title: "Download Complete", body: item.title)
                        self.updateDockBadge()
                        self.runPostDownloadAction(for: item)
                        self.generateThumbnail(for: item)
                        self.verifyFileIntegrity(for: item)
                        self.scheduleQueuePersistence()
                    }
                } else {
                    DispatchQueue.main.async {
                        item.status = .failed("Video conversion failed. The video was downloaded but could not be converted.")
                        self.scheduleQueuePersistence()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    item.status = .failed("Download completed but output file could not be located.")
                    self.scheduleQueuePersistence()
                }
            }
        } else {
            // Non-macCompatible or audio job — just mark completed
            let finalPath: URL?
            if let captured = capturedOutputPath, FileManager.default.fileExists(atPath: captured.path) {
                finalPath = captured
            } else if isAudioJob {
                finalPath = Self.findMostRecentFile(in: outputDirectory, extension: format == .m4a ? "m4a" : "mp3")
            } else {
                finalPath = Self.findMostRecentFile(in: outputDirectory, extension: format.rawValue.lowercased())
            }
            DispatchQueue.main.async {
                item.outputPath = finalPath
                item.status = .completed
                self.historyManager.record(item: item)
                self.postNotification(title: "Download Complete", body: item.title)
                self.updateDockBadge()
                self.runPostDownloadAction(for: item)
                self.generateThumbnail(for: item)
                self.verifyFileIntegrity(for: item)
                self.scheduleQueuePersistence()
            }
        }
    }

    /// Runs ffmpeg with the given codec and returns true if it succeeded.
    /// Updates item.status with processing progress as ffmpeg runs.
    @discardableResult
    private func runFfmpeg(
        ffmpegPath: String,
        input: String,
        output: String,
        videoCodec: String,
        codecArgs: [String],
        totalSeconds: Double,
        item: DownloadItem
    ) -> Bool {
        // Reset progress display for retry attempts
        DispatchQueue.main.async {
            item.status = .processing(progress: 0)
            self.scheduleQueuePersistence()
        }

        let ffmpeg = Process()
        ffmpeg.executableURL = URL(fileURLWithPath: ffmpegPath)
        var ffmpegArgs = ["-y", "-i", input, "-c:v", videoCodec]
            + codecArgs
        // -movflags +faststart is only valid for MP4/MOV containers
        let outputExt = (output as NSString).pathExtension.lowercased()
        if outputExt == "mp4" || outputExt == "mov" || outputExt == "m4a" {
            ffmpegArgs += ["-movflags", "+faststart"]
        }
        ffmpegArgs += ["-progress", "pipe:1", "-nostats", output]
        ffmpeg.arguments = ffmpegArgs
        ffmpeg.environment = buildCleanEnvironment()

        let outPipe = Pipe()
        let errPipe = Pipe()
        ffmpeg.standardOutput = outPipe
        ffmpeg.standardError = errPipe

        DispatchQueue.main.async { self.processes[item.id] = ffmpeg }

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
            // Find the last progress value in this batch and throttle UI updates to ~10/sec
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
                    DispatchQueue.main.async {
                        item.status = .processing(progress: pct)
                        self?.scheduleQueuePersistence()
                    }
                }
            }
        }

        guard (try? ffmpeg.run()) != nil else {
            DispatchQueue.main.async {
                self.processes.removeValue(forKey: item.id)
                self.scheduleQueuePersistence()
            }
            return false
        }
        ffmpeg.waitUntilExit()
        outPipe.fileHandleForReading.readabilityHandler = nil
        DispatchQueue.main.async {
            self.processes.removeValue(forKey: item.id)
            self.scheduleQueuePersistence()
        }
        return ffmpeg.terminationStatus == 0
    }

    /// Uses ffprobe to get the duration of a video file in seconds. Returns 0 on failure.
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

    /// Verifies file integrity by running ffprobe on the output.
    /// Returns true if file is valid media, false otherwise.
    private func verifyFileIntegrity(for item: DownloadItem) {
        guard let outputPath = item.outputPath,
              FileManager.default.fileExists(atPath: outputPath.path) else { return }

        let ffprobePath = ytdlpPath
            .replacingOccurrences(of: "yt-dlp", with: "ffprobe")
        guard FileManager.default.fileExists(atPath: ffprobePath) else { return }

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffprobePath)
            process.arguments = [
                "-v", "error",
                "-show_entries", "format=duration,size",
                "-of", "default=noprint_wrappers=1",
                outputPath.path
            ]
            process.standardOutput = Pipe()
            let errPipe = Pipe()
            process.standardError = errPipe
            process.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
            try? process.run()
            process.waitUntilExit()

            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errOutput = String(data: errData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 || !errOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                DispatchQueue.main.async {
                    item.integrityWarning = errOutput.isEmpty ? "File may be corrupted" : errOutput.prefix(200).description
                    self.scheduleQueuePersistence()
                }
            }
        }
    }

    /// Extracts a thumbnail frame from a downloaded video using ffmpeg.
    /// Runs on a background thread and updates the item's localThumbnail on completion.
    private func generateThumbnail(for item: DownloadItem) {
        guard let outputPath = item.outputPath,
              FileManager.default.fileExists(atPath: outputPath.path) else { return }
        // Skip audio-only files
        let ext = outputPath.pathExtension.lowercased()
        if ext == "mp3" || ext == "m4a" { return }

        let ffmpegPath = ytdlpPath.replacingOccurrences(of: "yt-dlp", with: "ffmpeg")
        guard FileManager.default.fileExists(atPath: ffmpegPath) else { return }

        let thumbDir = FileManager.default.temporaryDirectory.appendingPathComponent("StarDownloaderThumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: thumbDir, withIntermediateDirectories: true)
        let thumbPath = thumbDir.appendingPathComponent("\(item.id.uuidString).jpg")

        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpegPath)
            process.arguments = [
                "-i", outputPath.path,
                "-vframes", "1",
                "-ss", "5",       // 5 seconds in for a meaningful frame
                "-vf", "scale=160:-1",
                "-y",
                thumbPath.path
            ]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            process.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
            try? process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 && FileManager.default.fileExists(atPath: thumbPath.path) {
                DispatchQueue.main.async {
                    item.localThumbnail = thumbPath
                    self.scheduleQueuePersistence()
                }
            }
        }
    }

    /// Finds the most recently modified file with the given extension in a directory (including subdirectories).
    private static func findMostRecentFile(in directory: URL, extension ext: String) -> URL? {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var best: (url: URL, date: Date)? = nil
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == ext.lowercased() else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  let date = values.contentModificationDate else { continue }
            if best == nil || date > best!.date {
                best = (fileURL, date)
            }
        }
        return best?.url
    }

    /// Extracts a user-friendly error message from yt-dlp stderr output.
    private static func extractUserFriendlyError(from stderr: String, exitCode: Int32) -> String {
        let lines = stderr.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        // Look for yt-dlp ERROR: lines first (most specific)
        if let errorLine = lines.last(where: { $0.hasPrefix("ERROR:") }) {
            let msg = String(errorLine.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return cleanErrorMessage(msg)
        }

        // Look for any line containing "error" keyword
        if let errorLine = lines.last(where: { $0.localizedCaseInsensitiveContains("error") && !$0.isEmpty }) {
            return cleanErrorMessage(errorLine)
        }

        return "Download failed (exit code \(exitCode))"
    }

    private static func cleanErrorMessage(_ msg: String) -> String {
        // Strip technical prefixes that aren't user-friendly
        var cleaned = msg
        for prefix in ["[youtube]", "[generic]", "[download]", "WARNING:", "ERROR:"] {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Map common yt-dlp errors to plain English
        if cleaned.localizedCaseInsensitiveContains("private video") {
            return "This video is private."
        }
        if cleaned.localizedCaseInsensitiveContains("not available") || cleaned.localizedCaseInsensitiveContains("unavailable") {
            return "This video is not available in your region or has been removed."
        }
        if cleaned.localizedCaseInsensitiveContains("age") && cleaned.localizedCaseInsensitiveContains("restricted") {
            return "This video is age-restricted and requires sign-in."
        }
        if cleaned.localizedCaseInsensitiveContains("sign in") || cleaned.localizedCaseInsensitiveContains("login") {
            return "This video requires you to be signed in."
        }
        if cleaned.localizedCaseInsensitiveContains("copyright") {
            return "This video is not available due to a copyright claim."
        }
        if cleaned.localizedCaseInsensitiveContains("live") && cleaned.localizedCaseInsensitiveContains("not supported") {
            return "Live streams are not supported."
        }

        // Truncate very long messages
        if cleaned.count > 150 {
            cleaned = String(cleaned.prefix(150)) + "…"
        }
        return cleaned.isEmpty ? "Download failed" : cleaned
    }

    // MARK: - Environment

    /// Cached clean environment — built once and reused across all process launches.
    private static let _cleanEnvironment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "DYLD_INSERT_LIBRARIES")
        env.removeValue(forKey: "DYLD_LIBRARY_PATH")
        env.removeValue(forKey: "DYLD_FRAMEWORK_PATH")
        let appBin = appBinDirectory.path
        let path = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = appBin + ":/opt/homebrew/bin:/usr/local/bin:" + path
        return env
    }()

    private func buildCleanEnvironment() -> [String: String] {
        Self._cleanEnvironment
    }

    // MARK: - Line Parsing

    private static func parseLine(
        _ line: String,
        currentOutputPath: URL?
    ) -> (status: DownloadStatus?, outputPath: URL?, title: String?, channel: String?, isLive: Bool?) {

        // Detect live stream
        if line.contains("is_live") || line.contains("[live]") || line.contains("live stream") {
            return (nil, nil, nil, nil, true)
        }

        // Progress: [download]  45.3% of 123.45MiB at 2.34MiB/s ETA 00:30
        if line.contains("[download]") && line.contains("%") {
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            var progress: Double = 0
            var speed = "—"
            var eta = "—"
            for (i, part) in parts.enumerated() {
                if part.hasSuffix("%"), let pct = Double(part.dropLast()) {
                    progress = min(max(pct / 100.0, 0), 1)
                }
                if part == "at", i + 1 < parts.count { speed = parts[i + 1] }
                if part == "ETA", i + 1 < parts.count { eta = parts[i + 1] }
            }
            return (.downloading(progress: progress, speed: speed, eta: eta), nil, nil, nil, nil)
        }

        // Destination: /path/to/file
        if line.contains("Destination:"), let range = line.range(of: "Destination: ") {
            let path = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty { return (nil, URL(fileURLWithPath: path), nil, nil, nil) }
        }

        // [Merger] Merging formats into "/path/to/file"
        if line.hasPrefix("[Merger] Merging formats into") {
            if let start = line.firstIndex(of: "\""), let end = line.lastIndex(of: "\""), start != end {
                let path = String(line[line.index(after: start)..<end])
                return (.processing(progress: 0), URL(fileURLWithPath: path), nil, nil, nil)
            }
            return (.processing(progress: 0), nil, nil, nil, nil)
        }

        if line.hasPrefix("[ExtractAudio]") {
            if line.contains("Destination:"), let range = line.range(of: "Destination: ") {
                let path = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty { return (.processing(progress: 0), URL(fileURLWithPath: path), nil, nil, nil) }
            }
            return (.processing(progress: 0), nil, nil, nil, nil)
        }

        // [ffmpeg] postprocessor output
        if line.hasPrefix("[ffmpeg]") || line.hasPrefix("[VideoConvertor]") {
            if line.contains("Destination:"), let range = line.range(of: "Destination: ") {
                let path = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !path.isEmpty { return (.processing(progress: 0), URL(fileURLWithPath: path), nil, nil, nil) }
            }
            return (.processing(progress: 0), nil, nil, nil, nil)
        }

        // Parse title from yt-dlp info lines
        if line.hasPrefix("[info]") && line.contains(":") {
            if let range = line.range(of: "Title: ") {
                let title = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { return (nil, nil, title, nil, nil) }
            }
        }

        return (nil, nil, nil, nil, nil)
    }

    // MARK: - Notifications

    func postNotification(title: String, body: String) {
        guard settings.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Dock Badge

    func updateDockBadge() {
        let active = items.filter { $0.status.isActive }.count
        DispatchQueue.main.async {
            NSApp.dockTile.badgeLabel = active > 0 ? "\(active)" : nil
        }
    }

    // MARK: - Clipboard Monitoring

    private var clipboardTimer: Timer?
    private var lastClipboardChangeCount: Int = 0

    func startClipboardMonitoring() {
        stopClipboardMonitoring()
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stopClipboardMonitoring() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
    }

    private func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastClipboardChangeCount else { return }
        lastClipboardChangeCount = currentCount

        guard let content = NSPasteboard.general.string(forType: .string) else { return }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host, host.contains(".")
        else { return }

        // Only notify for known video platforms to avoid noise
        let videoHosts = [
            "youtube.com", "youtu.be", "music.youtube.com",
            "vimeo.com", "tiktok.com", "twitter.com", "x.com",
            "instagram.com", "reddit.com", "dailymotion.com",
            "twitch.tv", "facebook.com", "fb.watch",
            "bilibili.com", "nicovideo.jp", "soundcloud.com"
        ]
        let isVideoURL = videoHosts.contains { host.contains($0) }

        guard isVideoURL else { return }
        guard !isDuplicate(url: trimmed) else { return }

        if settings.clipboardAction == .addToQueue {
            guard isYtdlpInstalled else {
                postNotification(
                    title: "Clipboard URL Detected",
                    body: "Install yt-dlp before auto-adding copied video URLs."
                )
                return
            }
            let added = addDownload(url: trimmed)
            if added {
                postNotification(
                    title: "Added from Clipboard",
                    body: "A copied video URL was added to your queue."
                )
            } else {
                postNotification(
                    title: "Clipboard URL Skipped",
                    body: "The copied video URL could not be added right now."
                )
            }
        } else {
            postNotification(
                title: "Video URL Detected",
                body: "A video URL was copied. Open the app to download it."
            )
        }
    }

    // MARK: - Scheduled Downloads

    private var scheduleTimer: Timer?

    func setupScheduler() {
        scheduleTimer?.invalidate()
        let hasFutureScheduledItems = items.contains {
            if let scheduledStartDate = $0.scheduledStartDate {
                return scheduledStartDate > Date()
            }
            return false
        }
        guard settings.scheduledDownloadEnabled || hasFutureScheduledItems else { return }
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkSchedule()
        }
    }

    private func checkSchedule() {
        startNextWaiting()
    }

    // MARK: - Post-download Actions

    func runPostDownloadAction(for item: DownloadItem) {
        guard settings.postDownloadAction != "none" else { return }
        switch settings.postDownloadAction {
        case "open":
            if let path = item.outputPath {
                NSWorkspace.shared.open(path)
            }
        case "reveal":
            openInFinder(item)
        case "script":
            if !settings.postDownloadScript.isEmpty, let path = item.outputPath?.path {
                let script = settings.postDownloadScript
                DispatchQueue.global(qos: .utility).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/bin/sh")
                    // Use shell variable to safely pass the file path, avoiding command injection
                    let safeCommand = script
                        .replacingOccurrences(of: "{file}", with: "\"$DOWNLOAD_FILE\"")
                        .replacingOccurrences(of: "{title}", with: "\"$DOWNLOAD_TITLE\"")
                        .replacingOccurrences(of: "{url}", with: "\"$DOWNLOAD_URL\"")
                    process.arguments = ["-c", safeCommand]
                    var env = ProcessInfo.processInfo.environment
                    env["DOWNLOAD_FILE"] = path
                    env["DOWNLOAD_TITLE"] = item.title
                    env["DOWNLOAD_URL"] = item.url
                    process.environment = env
                    try? process.run()
                    process.waitUntilExit()
                }
            }
        default:
            break
        }
    }

    // MARK: - Import/Export Queue

    func exportQueue() -> Data? {
        struct QueueEntry: Codable {
            let url: String
            let quality: String
            let format: String
            let subtitles: Bool
            let status: String
            let scheduledStartDate: Date?
        }
        let entries = items.map { item in
            let statusStr: String
            switch item.status {
            case .waiting: statusStr = "waiting"
            case .completed: statusStr = "completed"
            case .failed: statusStr = "failed"
            case .cancelled: statusStr = "cancelled"
                default: statusStr = "active"
            }
            return QueueEntry(
                url: item.url,
                quality: item.quality.rawValue,
                format: item.format.rawValue,
                subtitles: item.subtitles,
                status: statusStr,
                scheduledStartDate: item.scheduledStartDate
            )
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        return try? encoder.encode(entries)
    }

    func importQueue(from data: Data) {
        struct QueueEntry: Codable {
            let url: String
            let quality: String
            let format: String
            let subtitles: Bool
            let scheduledStartDate: Date?
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([QueueEntry].self, from: data) else { return }
        for entry in entries {
            let q = VideoQuality(rawValue: entry.quality) ?? settings.defaultQuality
            let f = OutputFormat(rawValue: entry.format) ?? settings.defaultFormat
            if !isDuplicate(url: entry.url) {
                addDownload(
                    url: entry.url,
                    quality: q,
                    format: f,
                    subtitles: entry.subtitles,
                    scheduledStartDate: entry.scheduledStartDate
                )
            }
        }
    }

    // MARK: - Launch at Login

    func updateLoginItem() {
        do {
            if settings.launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently fail — user can manage in System Settings
        }
    }

    // MARK: - App Support Directory

    static func appSupportDirectory() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Star Video Downloader")
        if !fm.fileExists(atPath: appDir.path) {
            try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        return appDir
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600; let m = (seconds % 3600) / 60; let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
