//
//  ConversionItem.swift
//  Youtube downloader
//

import Foundation

enum ConversionStatus: Equatable {
    case waiting
    case converting(progress: Double)
    case completed
    case failed(String)
    case cancelled

    var displayText: String {
        switch self {
        case .waiting: return "Waiting"
        case .converting(let p): return p > 0 ? "Converting… \(Int(p * 100))%" : "Converting…"
        case .completed: return "Completed"
        case .failed(let msg): return "Failed: \(msg)"
        case .cancelled: return "Cancelled"
        }
    }

    var isActive: Bool {
        switch self {
        case .waiting, .converting: return true
        default: return false
        }
    }
}

@Observable
class ConversionItem: Identifiable {
    let id = UUID()
    var inputPath: URL
    var outputPath: URL?
    var fileName: String
    var title: String?
    var fileSize: String
    var status: ConversionStatus
    var videoCodec: VideoCodec
    var audioCodec: AudioCodec
    var encodingQuality: EncodingQuality
    var outputFormat: String
    var processingOptions: VideoProcessingOptions
    var audioOnly: Bool
    var addedDate: Date

    init(
        inputPath: URL,
        videoCodec: VideoCodec = .h264,
        audioCodec: AudioCodec = .aac,
        encodingQuality: EncodingQuality = .medium,
        outputFormat: String = "mp4",
        processingOptions: VideoProcessingOptions = VideoProcessingOptions(),
        audioOnly: Bool = false
    ) {
        self.inputPath = inputPath
        self.fileName = inputPath.lastPathComponent
        self.status = .waiting
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.encodingQuality = encodingQuality
        self.outputFormat = outputFormat
        self.processingOptions = processingOptions
        self.audioOnly = audioOnly
        self.addedDate = Date()

        // Get file size
        if let attrs = try? FileManager.default.attributesOfItem(atPath: inputPath.path),
           let size = attrs[.size] as? Int64 {
            self.fileSize = ConversionItem.formatFileSize(size)
        } else {
            self.fileSize = "—"
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func formatFileSize(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: bytes)
    }
}
