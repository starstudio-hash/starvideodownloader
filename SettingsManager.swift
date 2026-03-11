//
//  SettingsManager.swift
//  Youtube downloader
//

import Foundation

enum DuplicateHandlingMode: String, CaseIterable, Identifiable {
    case ask = "Ask"
    case skip = "Skip"
    case allow = "Allow"

    var id: String { rawValue }
}

enum ClipboardMonitorAction: String, CaseIterable, Identifiable {
    case notify = "Notify"
    case addToQueue = "Add to Queue"

    var id: String { rawValue }
}

enum SettingsPresentationMode: String, CaseIterable, Identifiable {
    case simple = "Simple"
    case advanced = "Advanced"

    var id: String { rawValue }
}

@Observable
class SettingsManager {

    // MARK: - Download Defaults

    var defaultQuality: VideoQuality = .best1080
    var defaultFormat: OutputFormat = .mp4
    var downloadSubtitlesByDefault: Bool = false
    var macCompatibleEncoding: Bool = true
    var encodingQuality: EncodingQuality = .medium
    var selectedVideoCodec: VideoCodec = .h264
    var selectedAudioCodec: AudioCodec = .aac
    var outputDirectory: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser

    // MARK: - yt-dlp Flags

    var cookiesFromBrowser: String = "none"
    var rateLimitEnabled: Bool = false
    var rateLimitSpeed: String = "2M"
    var useDownloadArchive: Bool = false
    var sponsorBlockEnabled: Bool = false
    var sponsorBlockMode: String = "all"
    var embedThumbnail: Bool = false
    var embedMetadata: Bool = false
    var embedChapters: Bool = false
    var splitChapters: Bool = false
    var geoBypass: Bool = false
    var geoBypassCountry: String = ""
    var concurrentFragments: Int = 1
    var playlistItemsFilter: String = ""
    var matchFilter: String = ""

    // MARK: - macOS Integration

    var notificationsEnabled: Bool = true
    var clipboardMonitoring: Bool = false
    var clipboardAction: ClipboardMonitorAction = .notify
    var launchAtLogin: Bool = false

    // MARK: - Metadata & Organization

    var filenameTemplate: String = "%(title)s.%(ext)s"
    var autoOrganize: Bool = false
    var organizeBy: String = "none"
    var duplicateHandling: DuplicateHandlingMode = .ask

    // MARK: - Advanced

    var scheduledDownloadEnabled: Bool = false
    var scheduledDownloadTime: Date = Calendar.current.date(from: DateComponents(hour: 2, minute: 0)) ?? Date()
    var postDownloadAction: String = "none"
    var postDownloadScript: String = ""
    var settingsPresentationMode: SettingsPresentationMode = .simple
    var lastScheduledRunDate: Date? = nil

    // MARK: - Live Streams

    var liveFromStart: Bool = false
    var waitForVideo: Bool = false

    // MARK: - Sleep Intervals
    var sleepIntervalEnabled: Bool = false
    var sleepIntervalMin: Int = 3
    var sleepIntervalMax: Int = 10

    // MARK: - Format Sorting
    var formatSortString: String = ""

    // MARK: - Embed Subtitles
    var embedSubtitles: Bool = false

    // MARK: - File Conflict Behavior
    var fileConflictBehavior: String = "rename"  // skip, overwrite, rename

    // MARK: - Per-Site Authentication
    var cookiesFilePath: String = ""

    // MARK: - Convert Thumbnails
    var convertThumbnailsFormat: String = ""  // "", "jpg", "png"

    // MARK: - Concurrency

    var maxConcurrentDownloads: Int = 3

    // MARK: - Persistence

    private var _saveDebounceWork: DispatchWorkItem?

    private enum Keys {
        static let quality = "defaultQuality"
        static let format = "defaultFormat"
        static let subtitles = "downloadSubtitles"
        static let outputDir = "outputDirectory"
        static let macCompat = "macCompatibleEncoding"
        static let encQuality = "encodingQuality"
        static let maxConcurrent = "maxConcurrentDownloads"
        static let videoCodec = "selectedVideoCodec"
        static let audioCodec = "selectedAudioCodec"
        static let cookiesBrowser = "cookiesFromBrowser"
        static let rateLimit = "rateLimitEnabled"
        static let rateLimitSpeed = "rateLimitSpeed"
        static let downloadArchive = "useDownloadArchive"
        static let sponsorBlock = "sponsorBlockEnabled"
        static let sponsorBlockMode = "sponsorBlockMode"
        static let embedThumb = "embedThumbnail"
        static let embedMeta = "embedMetadata"
        static let embedChapters = "embedChapters"
        static let splitChapters = "splitChapters"
        static let geoBypass = "geoBypass"
        static let geoBypassCountry = "geoBypassCountry"
        static let concFragments = "concurrentFragments"
        static let playlistItems = "playlistItemsFilter"
        static let matchFilter = "matchFilter"
        static let notifications = "notificationsEnabled"
        static let clipboard = "clipboardMonitoring"
        static let clipboardAction = "clipboardAction"
        static let loginItem = "launchAtLogin"
        static let fnTemplate = "filenameTemplate"
        static let autoOrg = "autoOrganize"
        static let orgBy = "organizeBy"
        static let duplicateHandling = "duplicateHandling"
        static let schedEnabled = "scheduledDownloadEnabled"
        static let schedTime = "scheduledDownloadTime"
        static let postAction = "postDownloadAction"
        static let postScript = "postDownloadScript"
        static let settingsMode = "settingsPresentationMode"
        static let lastScheduledRunDate = "lastScheduledRunDate"
        static let liveFromStart = "liveFromStart"
        static let waitForVideo = "waitForVideo"
        static let sleepIntervalEnabled = "sleepIntervalEnabled"
        static let sleepIntervalMin = "sleepIntervalMin"
        static let sleepIntervalMax = "sleepIntervalMax"
        static let formatSortString = "formatSortString"
        static let embedSubtitles = "embedSubtitles"
        static let fileConflictBehavior = "fileConflictBehavior"
        static let cookiesFilePath = "cookiesFilePath"
        static let convertThumbnailsFormat = "convertThumbnailsFormat"
    }

    init() {
        let d = UserDefaults.standard
        if let raw = d.string(forKey: Keys.quality), let q = VideoQuality(rawValue: raw) { defaultQuality = q }
        if let raw = d.string(forKey: Keys.format), let f = OutputFormat(rawValue: raw) { defaultFormat = f }
        if d.object(forKey: Keys.subtitles) != nil { downloadSubtitlesByDefault = d.bool(forKey: Keys.subtitles) }
        if d.object(forKey: Keys.macCompat) != nil { macCompatibleEncoding = d.bool(forKey: Keys.macCompat) }
        if let raw = d.string(forKey: Keys.encQuality), let eq = EncodingQuality(rawValue: raw) { encodingQuality = eq }
        if d.object(forKey: Keys.maxConcurrent) != nil {
            let v = d.integer(forKey: Keys.maxConcurrent)
            if (1...10).contains(v) { maxConcurrentDownloads = v }
        }
        if let raw = d.string(forKey: Keys.videoCodec), let vc = VideoCodec(rawValue: raw) { selectedVideoCodec = vc }
        if let raw = d.string(forKey: Keys.audioCodec), let ac = AudioCodec(rawValue: raw) { selectedAudioCodec = ac }
        if let raw = d.string(forKey: Keys.cookiesBrowser) { cookiesFromBrowser = raw }
        if d.object(forKey: Keys.rateLimit) != nil { rateLimitEnabled = d.bool(forKey: Keys.rateLimit) }
        if let raw = d.string(forKey: Keys.rateLimitSpeed) { rateLimitSpeed = raw }
        if d.object(forKey: Keys.downloadArchive) != nil { useDownloadArchive = d.bool(forKey: Keys.downloadArchive) }
        if d.object(forKey: Keys.sponsorBlock) != nil { sponsorBlockEnabled = d.bool(forKey: Keys.sponsorBlock) }
        if let raw = d.string(forKey: Keys.sponsorBlockMode) { sponsorBlockMode = raw }
        if d.object(forKey: Keys.embedThumb) != nil { embedThumbnail = d.bool(forKey: Keys.embedThumb) }
        if d.object(forKey: Keys.embedMeta) != nil { embedMetadata = d.bool(forKey: Keys.embedMeta) }
        if d.object(forKey: Keys.embedChapters) != nil { embedChapters = d.bool(forKey: Keys.embedChapters) }
        if d.object(forKey: Keys.splitChapters) != nil { splitChapters = d.bool(forKey: Keys.splitChapters) }
        if d.object(forKey: Keys.geoBypass) != nil { geoBypass = d.bool(forKey: Keys.geoBypass) }
        if let raw = d.string(forKey: Keys.geoBypassCountry) { geoBypassCountry = raw }
        if d.object(forKey: Keys.concFragments) != nil {
            let v = d.integer(forKey: Keys.concFragments)
            if (1...8).contains(v) { concurrentFragments = v }
        }
        if let raw = d.string(forKey: Keys.playlistItems) { playlistItemsFilter = raw }
        if let raw = d.string(forKey: Keys.matchFilter) { matchFilter = raw }
        if d.object(forKey: Keys.notifications) != nil { notificationsEnabled = d.bool(forKey: Keys.notifications) }
        if d.object(forKey: Keys.clipboard) != nil { clipboardMonitoring = d.bool(forKey: Keys.clipboard) }
        if let raw = d.string(forKey: Keys.clipboardAction), let action = ClipboardMonitorAction(rawValue: raw) {
            clipboardAction = action
        }
        if d.object(forKey: Keys.loginItem) != nil { launchAtLogin = d.bool(forKey: Keys.loginItem) }
        if let raw = d.string(forKey: Keys.fnTemplate), !raw.isEmpty { filenameTemplate = raw }
        if d.object(forKey: Keys.autoOrg) != nil { autoOrganize = d.bool(forKey: Keys.autoOrg) }
        if let raw = d.string(forKey: Keys.orgBy) { organizeBy = raw }
        if let raw = d.string(forKey: Keys.duplicateHandling), let handling = DuplicateHandlingMode(rawValue: raw) {
            duplicateHandling = handling
        }
        if d.object(forKey: Keys.schedEnabled) != nil { scheduledDownloadEnabled = d.bool(forKey: Keys.schedEnabled) }
        if d.object(forKey: Keys.schedTime) != nil, let date = d.object(forKey: Keys.schedTime) as? Date { scheduledDownloadTime = date }
        if let raw = d.string(forKey: Keys.postAction) { postDownloadAction = raw }
        if let raw = d.string(forKey: Keys.postScript) { postDownloadScript = raw }
        if let raw = d.string(forKey: Keys.settingsMode), let mode = SettingsPresentationMode(rawValue: raw) {
            settingsPresentationMode = mode
        }
        lastScheduledRunDate = d.object(forKey: Keys.lastScheduledRunDate) as? Date
        if d.object(forKey: Keys.liveFromStart) != nil { liveFromStart = d.bool(forKey: Keys.liveFromStart) }
        if d.object(forKey: Keys.waitForVideo) != nil { waitForVideo = d.bool(forKey: Keys.waitForVideo) }
        if d.object(forKey: Keys.sleepIntervalEnabled) != nil { sleepIntervalEnabled = d.bool(forKey: Keys.sleepIntervalEnabled) }
        if d.object(forKey: Keys.sleepIntervalMin) != nil {
            let v = d.integer(forKey: Keys.sleepIntervalMin)
            if (0...60).contains(v) { sleepIntervalMin = v }
        }
        if d.object(forKey: Keys.sleepIntervalMax) != nil {
            let v = d.integer(forKey: Keys.sleepIntervalMax)
            if (0...120).contains(v) { sleepIntervalMax = v }
        }
        if let raw = d.string(forKey: Keys.formatSortString) { formatSortString = raw }
        if d.object(forKey: Keys.embedSubtitles) != nil { embedSubtitles = d.bool(forKey: Keys.embedSubtitles) }
        if let raw = d.string(forKey: Keys.fileConflictBehavior) { fileConflictBehavior = raw }
        if let raw = d.string(forKey: Keys.cookiesFilePath) { cookiesFilePath = raw }
        if let raw = d.string(forKey: Keys.convertThumbnailsFormat) { convertThumbnailsFormat = raw }
        if let path = d.string(forKey: Keys.outputDir) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                outputDirectory = URL(fileURLWithPath: path)
            }
        }
    }

    /// Debounced save — coalesces multiple rapid onChange calls into a single UserDefaults write.
    func saveSettings() {
        _saveDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?._writeAllSettings()
        }
        _saveDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func _writeAllSettings() {
        let d = UserDefaults.standard
        d.set(defaultQuality.rawValue, forKey: Keys.quality)
        d.set(defaultFormat.rawValue, forKey: Keys.format)
        d.set(downloadSubtitlesByDefault, forKey: Keys.subtitles)
        d.set(macCompatibleEncoding, forKey: Keys.macCompat)
        d.set(encodingQuality.rawValue, forKey: Keys.encQuality)
        d.set(maxConcurrentDownloads, forKey: Keys.maxConcurrent)
        d.set(selectedVideoCodec.rawValue, forKey: Keys.videoCodec)
        d.set(selectedAudioCodec.rawValue, forKey: Keys.audioCodec)
        d.set(cookiesFromBrowser, forKey: Keys.cookiesBrowser)
        d.set(rateLimitEnabled, forKey: Keys.rateLimit)
        d.set(rateLimitSpeed, forKey: Keys.rateLimitSpeed)
        d.set(useDownloadArchive, forKey: Keys.downloadArchive)
        d.set(sponsorBlockEnabled, forKey: Keys.sponsorBlock)
        d.set(sponsorBlockMode, forKey: Keys.sponsorBlockMode)
        d.set(embedThumbnail, forKey: Keys.embedThumb)
        d.set(embedMetadata, forKey: Keys.embedMeta)
        d.set(embedChapters, forKey: Keys.embedChapters)
        d.set(splitChapters, forKey: Keys.splitChapters)
        d.set(geoBypass, forKey: Keys.geoBypass)
        d.set(geoBypassCountry, forKey: Keys.geoBypassCountry)
        d.set(concurrentFragments, forKey: Keys.concFragments)
        d.set(playlistItemsFilter, forKey: Keys.playlistItems)
        d.set(matchFilter, forKey: Keys.matchFilter)
        d.set(notificationsEnabled, forKey: Keys.notifications)
        d.set(clipboardMonitoring, forKey: Keys.clipboard)
        d.set(clipboardAction.rawValue, forKey: Keys.clipboardAction)
        d.set(launchAtLogin, forKey: Keys.loginItem)
        d.set(filenameTemplate, forKey: Keys.fnTemplate)
        d.set(autoOrganize, forKey: Keys.autoOrg)
        d.set(organizeBy, forKey: Keys.orgBy)
        d.set(duplicateHandling.rawValue, forKey: Keys.duplicateHandling)
        d.set(scheduledDownloadEnabled, forKey: Keys.schedEnabled)
        d.set(scheduledDownloadTime, forKey: Keys.schedTime)
        d.set(postDownloadAction, forKey: Keys.postAction)
        d.set(postDownloadScript, forKey: Keys.postScript)
        d.set(settingsPresentationMode.rawValue, forKey: Keys.settingsMode)
        d.set(lastScheduledRunDate, forKey: Keys.lastScheduledRunDate)
        d.set(outputDirectory.path, forKey: Keys.outputDir)
        d.set(liveFromStart, forKey: Keys.liveFromStart)
        d.set(waitForVideo, forKey: Keys.waitForVideo)
        d.set(sleepIntervalEnabled, forKey: Keys.sleepIntervalEnabled)
        d.set(sleepIntervalMin, forKey: Keys.sleepIntervalMin)
        d.set(sleepIntervalMax, forKey: Keys.sleepIntervalMax)
        d.set(formatSortString, forKey: Keys.formatSortString)
        d.set(embedSubtitles, forKey: Keys.embedSubtitles)
        d.set(fileConflictBehavior, forKey: Keys.fileConflictBehavior)
        d.set(cookiesFilePath, forKey: Keys.cookiesFilePath)
        d.set(convertThumbnailsFormat, forKey: Keys.convertThumbnailsFormat)
    }
}
