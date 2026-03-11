import Foundation

enum BackendHealthSeverity: String, Codable {
    case info
    case warning
    case error
}

struct BackendHealthIssue: Identifiable, Equatable, Codable {
    let id: UUID
    var severity: BackendHealthSeverity
    var title: String
    var message: String

    init(id: UUID = UUID(), severity: BackendHealthSeverity, title: String, message: String) {
        self.id = id
        self.severity = severity
        self.title = title
        self.message = message
    }
}

struct URLInspectionResult {
    var title: String?
    var channel: String?
    var durationText: String?
    var thumbnailURL: URL?
    var isLiveStream: Bool
    var isPlaylist: Bool
    var playlistTitle: String?
    var playlistCount: Int
    var playlistEntries: [PlaylistEntryPreview] = []
}

struct PlaylistEntryPreview: Identifiable, Codable, Hashable {
    var sourcePlaylistURL: String
    var title: String
    var index: Int
    var webpageURL: String?
    var channel: String?
    var durationText: String?

    var id: String {
        "\(sourcePlaylistURL)#\(index)"
    }
}

enum URLInspectionError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

enum PersistedDownloadStatusKind: String, Codable {
    case waiting
    case fetchingInfo
    case downloading
    case processing
    case paused
    case completed
    case failed
    case cancelled
}

struct PersistedDownloadStatus: Codable {
    var kind: PersistedDownloadStatusKind
    var progress: Double?
    var speed: String?
    var eta: String?
    var message: String?

    init(from status: DownloadStatus) {
        switch status {
        case .waiting:
            kind = .waiting
        case .fetchingInfo:
            kind = .fetchingInfo
        case .downloading(let progress, let speed, let eta):
            kind = .downloading
            self.progress = progress
            self.speed = speed
            self.eta = eta
        case .processing(let progress):
            kind = .processing
            self.progress = progress
        case .paused(let progress):
            kind = .paused
            self.progress = progress
        case .completed:
            kind = .completed
        case .failed(let message):
            kind = .failed
            self.message = message
        case .cancelled:
            kind = .cancelled
        }
    }

    func restoredStatus() -> DownloadStatus {
        switch kind {
        case .waiting:
            return .waiting
        case .fetchingInfo, .downloading, .processing:
            return .failed("Interrupted by a previous app session. Retry to continue.")
        case .paused:
            return .paused(progress: progress ?? 0)
        case .completed:
            return .completed
        case .failed:
            return .failed(message ?? "Download failed.")
        case .cancelled:
            return .cancelled
        }
    }
}

struct PersistedDownloadItem: Codable {
    var url: String
    var sourcePlaylistURL: String?
    var title: String
    var thumbnail: String?
    var channelName: String
    var duration: String
    var status: PersistedDownloadStatus
    var quality: String
    var format: String
    var outputPath: String?
    var addedDate: Date
    var subtitles: Bool
    var playlistDownload: Bool
    var playlistTitle: String?
    var playlistIndex: Int?
    var isLiveStream: Bool
    var localThumbnail: String?
    var integrityWarning: String?
    var speedHistory: [Double]
    var scheduledStartDate: Date?

    init(item: DownloadItem) {
        url = item.url
        sourcePlaylistURL = item.sourcePlaylistURL
        title = item.title
        thumbnail = item.thumbnail?.absoluteString
        channelName = item.channelName
        duration = item.duration
        status = PersistedDownloadStatus(from: item.status)
        quality = item.quality.rawValue
        format = item.format.rawValue
        outputPath = item.outputPath?.path
        addedDate = item.addedDate
        subtitles = item.subtitles
        playlistDownload = item.playlistDownload
        playlistTitle = item.playlistTitle
        playlistIndex = item.playlistIndex
        isLiveStream = item.isLiveStream
        localThumbnail = item.localThumbnail?.path
        integrityWarning = item.integrityWarning
        speedHistory = item.speedHistory
        scheduledStartDate = item.scheduledStartDate
    }

    func makeDownloadItem() -> DownloadItem {
        let item = DownloadItem(
            url: url,
            quality: VideoQuality(rawValue: quality) ?? .best1080,
            format: OutputFormat(rawValue: format) ?? .mp4,
            subtitles: subtitles,
            playlistDownload: playlistDownload,
            playlistTitle: playlistTitle,
            playlistIndex: playlistIndex,
            sourcePlaylistURL: sourcePlaylistURL,
            scheduledStartDate: scheduledStartDate
        )
        item.title = title
        if let thumbnail, let parsed = URL(string: thumbnail) {
            item.thumbnail = parsed
        }
        item.channelName = channelName
        item.duration = duration
        item.status = status.restoredStatus()
        item.outputPath = outputPath.map { URL(fileURLWithPath: $0) }
        item.addedDate = addedDate
        item.isLiveStream = isLiveStream
        if let localThumbnail {
            item.localThumbnail = URL(fileURLWithPath: localThumbnail)
        }
        item.integrityWarning = integrityWarning
        item.speedHistory = speedHistory
        return item
    }
}

struct PersistedDownloadQueue: Codable {
    var schemaVersion: Int = 1
    var savedAt: Date
    var items: [PersistedDownloadItem]
}
