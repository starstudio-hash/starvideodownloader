//
//  VideoCodec.swift
//  Youtube downloader
//

import Foundation

// MARK: - Hardware Capabilities

struct HardwareCapabilities {
    static let isAppleSilicon: Bool = {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }()

    static let macOSVersion: OperatingSystemVersion = {
        ProcessInfo.processInfo.operatingSystemVersion
    }()

    /// AV1 hardware encoding requires Apple Silicon + macOS 14+
    static var supportsAV1Hardware: Bool {
        isAppleSilicon && macOSVersion.majorVersion >= 14
    }

    /// HEVC hardware encoding requires macOS 11+ (available on both Intel and Apple Silicon with supported GPU)
    static var supportsHEVCHardware: Bool {
        macOSVersion.majorVersion >= 11
    }

    /// ProRes hardware encoding requires Apple Silicon
    static var supportsProResHardware: Bool {
        isAppleSilicon
    }
}

// MARK: - Video Codec

enum VideoCodec: String, CaseIterable, Identifiable {
    case h264 = "H.264"
    case hevc = "H.265 (HEVC)"
    case av1 = "AV1"
    case prores = "ProRes"
    case vp9 = "VP9"
    case copy = "Copy (no re-encode)"

    var id: String { rawValue }

    /// Primary hardware-accelerated encoder name for ffmpeg
    var hardwareEncoder: String? {
        switch self {
        case .h264:  return "h264_videotoolbox"
        case .hevc:  return HardwareCapabilities.supportsHEVCHardware ? "hevc_videotoolbox" : nil
        case .av1:   return HardwareCapabilities.supportsAV1Hardware ? "av1_videotoolbox" : nil
        case .prores: return HardwareCapabilities.supportsProResHardware ? "prores_videotoolbox" : nil
        case .vp9:   return nil // No hardware VP9 encoder on macOS
        case .copy:  return nil
        }
    }

    /// Software fallback encoder name for ffmpeg
    var softwareEncoder: String? {
        switch self {
        case .h264:  return "libx264"
        case .hevc:  return "libx265"
        case .av1:   return "libsvtav1"
        case .prores: return nil // No software ProRes encoder in standard ffmpeg
        case .vp9:   return "libvpx-vp9"
        case .copy:  return nil
        }
    }

    /// ffmpeg codec name for `-c:v` (uses "copy" for passthrough)
    var ffmpegCodecName: String {
        if self == .copy { return "copy" }
        return hardwareEncoder ?? softwareEncoder ?? "copy"
    }

    /// The preferred output container for this codec
    var preferredContainer: String {
        switch self {
        case .h264, .hevc, .av1: return "mp4"
        case .prores: return "mov"
        case .vp9: return "webm"
        case .copy: return "mkv"
        }
    }

    /// Quality arguments for VideoToolbox hardware encoders
    func hardwareQualityArgs(quality: EncodingQuality) -> [String] {
        switch self {
        case .h264, .hevc:
            return ["-q:v", "\(quality.vtQuality)"]
        case .av1:
            return ["-q:v", "\(quality.vtQuality)"]
        case .prores:
            // ProRes uses profile: 0=Proxy, 1=LT, 2=Standard, 3=HQ
            let profile: Int
            switch quality {
            case .high: profile = 3
            case .medium: profile = 2
            case .low: profile = 0
            }
            return ["-profile:v", "\(profile)"]
        default:
            return []
        }
    }

    /// Quality arguments for software fallback encoders
    func softwareQualityArgs(quality: EncodingQuality) -> [String] {
        switch self {
        case .h264:
            return ["-preset", "medium", "-crf", "\(quality.fallbackCrf)"]
        case .hevc:
            return ["-preset", "medium", "-crf", "\(quality.fallbackCrf)"]
        case .av1:
            // SVT-AV1 uses crf 18-50 range
            let crf: Int
            switch quality {
            case .high: crf = 22
            case .medium: crf = 30
            case .low: crf = 38
            }
            return ["-crf", "\(crf)", "-preset", "6"]
        case .vp9:
            let crf: Int
            switch quality {
            case .high: crf = 20
            case .medium: crf = 28
            case .low: crf = 36
            }
            return ["-crf", "\(crf)", "-b:v", "0", "-row-mt", "1"]
        default:
            return []
        }
    }

    /// Whether hardware encoding is available for this codec
    var isHardwareAvailable: Bool {
        hardwareEncoder != nil
    }

    /// Availability note for the UI
    var availabilityNote: String? {
        switch self {
        case .hevc where !HardwareCapabilities.supportsHEVCHardware:
            return "Hardware encoding requires macOS 11+"
        case .av1 where !HardwareCapabilities.supportsAV1Hardware:
            if !HardwareCapabilities.isAppleSilicon {
                return "Requires Apple Silicon Mac"
            }
            return "Requires macOS 14+"
        case .prores where !HardwareCapabilities.supportsProResHardware:
            return "Hardware encoding requires Apple Silicon"
        case .vp9:
            return "Software encoding only (slower)"
        default:
            return nil
        }
    }
}

// MARK: - Audio Codec

enum AudioCodec: String, CaseIterable, Identifiable {
    case aac = "AAC"
    case alac = "ALAC (Lossless)"
    case flac = "FLAC (Lossless)"
    case opus = "Opus"
    case ac3 = "AC3 (Dolby)"
    case eac3 = "EAC3 (Dolby+)"
    case copy = "Copy (no re-encode)"

    var id: String { rawValue }

    /// ffmpeg encoder name
    var ffmpegEncoder: String {
        switch self {
        case .aac:  return "aac"
        case .alac: return "alac"
        case .flac: return "flac"
        case .opus: return "libopus"
        case .ac3:  return "ac3"
        case .eac3: return "eac3"
        case .copy: return "copy"
        }
    }

    /// Quality/bitrate arguments for this audio codec
    func qualityArgs(quality: EncodingQuality) -> [String] {
        switch self {
        case .aac:
            let bitrate: String
            switch quality {
            case .high: bitrate = "256k"
            case .medium: bitrate = "192k"
            case .low: bitrate = "128k"
            }
            return ["-b:a", bitrate]
        case .opus:
            let bitrate: String
            switch quality {
            case .high: bitrate = "192k"
            case .medium: bitrate = "128k"
            case .low: bitrate = "96k"
            }
            return ["-b:a", bitrate]
        case .ac3, .eac3:
            let bitrate: String
            switch quality {
            case .high: bitrate = "640k"
            case .medium: bitrate = "448k"
            case .low: bitrate = "256k"
            }
            return ["-b:a", bitrate]
        case .alac, .flac:
            return [] // Lossless — no quality setting needed
        case .copy:
            return []
        }
    }

    /// Compatible containers for this codec
    var compatibleContainers: [String] {
        switch self {
        case .aac: return ["mp4", "m4a", "mkv", "mov"]
        case .alac: return ["m4a", "mov", "mp4"]
        case .flac: return ["flac", "mkv", "ogg"]
        case .opus: return ["webm", "ogg", "mkv"]
        case .ac3, .eac3: return ["mp4", "mkv", "mov"]
        case .copy: return ["mp4", "mkv", "webm", "mov"]
        }
    }
}
