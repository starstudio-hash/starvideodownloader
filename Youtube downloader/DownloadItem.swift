//
//  DownloadItem.swift
//  Youtube downloader
//

import Foundation
import SwiftUI

enum DownloadStatus: Equatable {
    case waiting
    case fetchingInfo
    case downloading(progress: Double, speed: String, eta: String)
    case processing(progress: Double)
    case paused(progress: Double)
    case completed
    case failed(String)
    case cancelled

    var displayText: String {
        switch self {
        case .waiting: return "Waiting"
        case .fetchingInfo: return "Fetching info..."
        case .downloading(let progress, let speed, let eta):
            let pct = Int(progress * 100)
            return "\(pct)% — \(speed) — ETA \(eta)"
        case .processing(let p): return p > 0 ? "Processing… \(Int(p * 100))%" : "Processing…"
        case .paused(let p): return "Paused — \(Int(p * 100))%"
        case .completed: return "Completed"
        case .failed(let msg): return "Failed: \(msg)"
        case .cancelled: return "Cancelled"
        }
    }

    var isActive: Bool {
        switch self {
        case .waiting, .fetchingInfo, .downloading, .processing, .paused: return true
        default: return false
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .waiting: return "Waiting to download"
        case .fetchingInfo: return "Fetching video information"
        case .downloading(let progress, _, _): return "Downloading, \(Int(progress * 100)) percent complete"
        case .processing(let p): return p > 0 ? "Converting, \(Int(p * 100)) percent complete" : "Converting"
        case .paused(let p): return "Paused at \(Int(p * 100)) percent"
        case .completed: return "Download complete"
        case .failed(let msg): return "Download failed: \(msg)"
        case .cancelled: return "Download cancelled"
        }
    }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case best4k = "2160p (4K)"
    case best2k = "1440p (2K)"
    case best1080 = "1080p"
    case best720 = "720p"
    case best480 = "480p"
    case best360 = "360p"
    case bestAudio = "Audio only"
    case best = "Best available"

    var id: String { rawValue }

    var isAudioOnly: Bool { self == .bestAudio }

    var ytdlpFormat: String {
        switch self {
        case .best4k: return "bestvideo[height<=2160]+bestaudio/best[height<=2160]"
        case .best2k: return "bestvideo[height<=1440]+bestaudio/best[height<=1440]"
        case .best1080: return "bestvideo[height<=1080]+bestaudio/best[height<=1080]"
        case .best720: return "bestvideo[height<=720]+bestaudio/best[height<=720]"
        case .best480: return "bestvideo[height<=480]+bestaudio/best[height<=480]"
        case .best360: return "bestvideo[height<=360]+bestaudio/best[height<=360]"
        case .bestAudio: return "bestaudio/best"
        case .best: return "bestvideo+bestaudio/best"
        }
    }
}

enum EncodingQuality: String, CaseIterable, Identifiable {
    case high   = "High"
    case medium = "Medium"
    case low    = "Low"

    var id: String { rawValue }

    /// VideoToolbox quality (1–100). Higher = better quality / larger file.
    var vtQuality: Int {
        switch self {
        case .high:   return 75
        case .medium: return 60
        case .low:    return 45
        }
    }

    /// x264 software fallback CRF. Lower = higher quality.
    var fallbackCrf: Int {
        switch self {
        case .high:   return 18
        case .medium: return 23
        case .low:    return 28
        }
    }

    var description: String {
        switch self {
        case .high:   return "Best quality, larger file"
        case .medium: return "Good quality, balanced file size"
        case .low:    return "Smaller file, fastest encode"
        }
    }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4"
    case mkv = "MKV"
    case mp3 = "MP3"
    case m4a = "M4A"
    case webm = "WebM"

    var id: String { rawValue }

    var isAudioOnly: Bool {
        self == .mp3 || self == .m4a
    }
}

@Observable
class DownloadItem: Identifiable {
    let id = UUID()
    var url: String
    var sourcePlaylistURL: String?
    var title: String
    var thumbnail: URL?
    var channelName: String
    var duration: String
    var status: DownloadStatus
    var quality: VideoQuality
    var format: OutputFormat
    var outputPath: URL?
    var addedDate: Date
    var subtitles: Bool
    var playlistDownload: Bool
    // Playlist grouping
    var playlistTitle: String?
    var playlistIndex: Int?
    // Live stream tracking
    var isLiveStream: Bool = false
    // Local thumbnail extracted from downloaded file
    var localThumbnail: URL?
    // File integrity warning (nil = passed verification)
    var integrityWarning: String?
    // Speed history for sparkline (last 20 samples in bytes/sec)
    var speedHistory: [Double] = []
    // Optional per-item scheduler timestamp
    var scheduledStartDate: Date?

    init(
        url: String,
        quality: VideoQuality = .best1080,
        format: OutputFormat = .mp4,
        subtitles: Bool = false,
        playlistDownload: Bool = false,
        playlistTitle: String? = nil,
        playlistIndex: Int? = nil,
        sourcePlaylistURL: String? = nil,
        scheduledStartDate: Date? = nil
    ) {
        self.url = url
        self.sourcePlaylistURL = sourcePlaylistURL
        self.title = url
        self.channelName = ""
        self.duration = ""
        self.status = .waiting
        self.quality = quality
        self.format = format
        self.addedDate = Date()
        self.subtitles = subtitles
        self.playlistDownload = playlistDownload
        self.playlistTitle = playlistTitle
        self.playlistIndex = playlistIndex
        self.scheduledStartDate = scheduledStartDate
    }
}
