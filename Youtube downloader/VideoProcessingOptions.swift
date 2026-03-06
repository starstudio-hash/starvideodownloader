//
//  VideoProcessingOptions.swift
//  Youtube downloader
//

import Foundation

enum ResolutionScale: String, CaseIterable, Identifiable {
    case original = "Original"
    case p2160 = "2160p (4K)"
    case p1440 = "1440p"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"
    case p360 = "360p"

    var id: String { rawValue }

    var ffmpegScale: String? {
        switch self {
        case .original: return nil
        case .p2160: return "-2:2160"
        case .p1440: return "-2:1440"
        case .p1080: return "-2:1080"
        case .p720:  return "-2:720"
        case .p480:  return "-2:480"
        case .p360:  return "-2:360"
        }
    }
}

enum SpeedMultiplier: String, CaseIterable, Identifiable {
    case x025 = "0.25x"
    case x05 = "0.5x"
    case x075 = "0.75x"
    case x1 = "1x (Normal)"
    case x125 = "1.25x"
    case x15 = "1.5x"
    case x2 = "2x"
    case x4 = "4x"

    var id: String { rawValue }

    var videoValue: Double {
        switch self {
        case .x025: return 4.0     // setpts=4*PTS (slower)
        case .x05:  return 2.0
        case .x075: return 1.333
        case .x1:   return 1.0
        case .x125: return 0.8
        case .x15:  return 0.667
        case .x2:   return 0.5
        case .x4:   return 0.25
        }
    }

    var audioValue: Double {
        switch self {
        case .x025: return 0.25
        case .x05:  return 0.5
        case .x075: return 0.75
        case .x1:   return 1.0
        case .x125: return 1.25
        case .x15:  return 1.5
        case .x2:   return 2.0
        case .x4:   return 4.0
        }
    }
}

enum CropPreset: String, CaseIterable, Identifiable {
    case custom = "Custom"
    case r16_9 = "16:9"
    case r4_3 = "4:3"
    case r1_1 = "1:1 (Square)"
    case r9_16 = "9:16 (Vertical)"

    var id: String { rawValue }

    /// Returns a crop filter string using input dimensions (iw/ih).
    var ffmpegCrop: String? {
        switch self {
        case .custom: return nil
        case .r16_9: return "crop=ih*16/9:ih"
        case .r4_3: return "crop=ih*4/3:ih"
        case .r1_1: return "crop=min(iw\\,ih):min(iw\\,ih)"
        case .r9_16: return "crop=ih*9/16:ih"
        }
    }
}

enum RotationOption: String, CaseIterable, Identifiable {
    case none = "None"
    case cw90 = "90° CW"
    case ccw90 = "90° CCW"
    case rotate180 = "180°"
    case hflip = "H-Flip"
    case vflip = "V-Flip"

    var id: String { rawValue }

    var ffmpegFilter: String? {
        switch self {
        case .none: return nil
        case .cw90: return "transpose=1"
        case .ccw90: return "transpose=2"
        case .rotate180: return "transpose=1,transpose=1"
        case .hflip: return "hflip"
        case .vflip: return "vflip"
        }
    }
}

enum ArtisticEffect: String, CaseIterable, Identifiable {
    case none = "None"
    case grayscale = "Grayscale"
    case sepia = "Sepia"
    case negative = "Negative"

    var id: String { rawValue }

    var ffmpegFilter: String? {
        switch self {
        case .none: return nil
        case .grayscale: return "hue=s=0"
        case .sepia: return "colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131"
        case .negative: return "negate"
        }
    }
}

@Observable
class VideoProcessingOptions {
    // Resolution
    var resolutionScale: ResolutionScale = .original

    // Trim
    var trimEnabled: Bool = false
    var trimStart: String = "00:00:00"
    var trimEnd: String = ""

    // Speed
    var speedEnabled: Bool = false
    var speed: SpeedMultiplier = .x1

    // Audio
    var normalizeVolume: Bool = false
    var noiseReduction: Bool = false

    // Video
    var deinterlace: Bool = false
    var hdrToSdr: Bool = false

    // Color Correction
    var colorCorrectionEnabled: Bool = false
    var brightness: Double = 0.0      // -1.0 to 1.0
    var contrast: Double = 1.0        // 0.0 to 3.0
    var saturation: Double = 1.0      // 0.0 to 3.0

    // Crop
    var cropEnabled: Bool = false
    var cropPreset: CropPreset = .custom
    var cropWidth: String = ""
    var cropHeight: String = ""
    var cropX: String = ""
    var cropY: String = ""

    // Rotation & Flip
    var rotation: RotationOption = .none

    // Text Overlay
    var textOverlayEnabled: Bool = false
    var overlayText: String = ""
    var textPosition: String = "bottom"  // top, bottom, center
    var textFontSize: Int = 24
    var textColor: String = "white"

    // Fade In/Out
    var fadeInEnabled: Bool = false
    var fadeInDuration: Double = 1.0
    var fadeOutEnabled: Bool = false
    var fadeOutDuration: Double = 1.0

    // Sharpen / Blur
    var sharpenEnabled: Bool = false
    var sharpenStrength: Double = 1.0    // 0.0 to 3.0
    var blurEnabled: Bool = false
    var blurStrength: Int = 2            // 1 to 10 (boxblur radius)

    // Artistic Effects
    var artisticEffect: ArtisticEffect = .none

    // Subtitle burn
    var burnSubtitles: Bool = false
    var subtitleFilePath: String = ""

    // GIF
    var extractGif: Bool = false
    var gifStart: String = "00:00:00"
    var gifDuration: String = "5"
    var gifWidth: Int = 480

    // Frame extraction
    var extractFrames: Bool = false
    var frameCount: Int = 1

    /// Builds the ffmpeg video filter chain (-vf argument)
    /// - Parameter totalDuration: Total video duration in seconds, needed for fade-out calculation
    func buildVideoFilters(totalDuration: Double = 0) -> [String] {
        var filters: [String] = []

        if let scale = resolutionScale.ffmpegScale {
            filters.append("scale=\(scale)")
        }

        if deinterlace {
            filters.append("yadif")
        }

        if hdrToSdr {
            filters.append("zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p")
        }

        if cropEnabled {
            if cropPreset != .custom, let cropStr = cropPreset.ffmpegCrop {
                filters.append(cropStr)
            } else if cropPreset == .custom {
                let w = cropWidth.isEmpty ? "iw" : cropWidth
                let h = cropHeight.isEmpty ? "ih" : cropHeight
                let x = cropX.isEmpty ? "(iw-\(w))/2" : cropX
                let y = cropY.isEmpty ? "(ih-\(h))/2" : cropY
                filters.append("crop=\(w):\(h):\(x):\(y)")
            }
        }

        if colorCorrectionEnabled {
            filters.append("eq=brightness=\(String(format: "%.2f", brightness)):contrast=\(String(format: "%.2f", contrast)):saturation=\(String(format: "%.2f", saturation))")
        }

        if sharpenEnabled {
            let amount = String(format: "%.1f", sharpenStrength)
            filters.append("unsharp=5:5:\(amount):5:5:\(amount)")
        }

        if blurEnabled {
            filters.append("boxblur=\(blurStrength):\(blurStrength)")
        }

        if artisticEffect != .none, let artFilter = artisticEffect.ffmpegFilter {
            filters.append(artFilter)
        }

        if rotation != .none, let rotFilter = rotation.ffmpegFilter {
            filters.append(rotFilter)
        }

        if textOverlayEnabled && !overlayText.isEmpty {
            let escaped = overlayText.replacingOccurrences(of: "'", with: "\\'")
            let yPos: String
            switch textPosition {
            case "top": yPos = "30"
            case "center": yPos = "(h-text_h)/2"
            default: yPos = "h-text_h-30"
            }
            filters.append("drawtext=text='\(escaped)':fontsize=\(textFontSize):fontcolor=\(textColor):x=(w-text_w)/2:y=\(yPos)")
        }

        if fadeInEnabled {
            filters.append("fade=t=in:st=0:d=\(String(format: "%.1f", fadeInDuration))")
        }

        if fadeOutEnabled && totalDuration > 0 {
            let startTime = max(0, totalDuration - fadeOutDuration)
            filters.append("fade=t=out:st=\(String(format: "%.1f", startTime)):d=\(String(format: "%.1f", fadeOutDuration))")
        }

        if speedEnabled && speed != .x1 {
            filters.append("setpts=\(speed.videoValue)*PTS")
        }

        return filters
    }

    /// Builds audio filter chain (-af argument)
    func buildAudioFilters() -> [String] {
        var filters: [String] = []

        if normalizeVolume {
            filters.append("loudnorm=I=-16:TP=-1.5:LRA=11")
        }

        if noiseReduction {
            filters.append("afftdn=nf=-20")
        }

        if speedEnabled && speed != .x1 {
            filters.append("atempo=\(speed.audioValue)")
        }

        return filters
    }

    /// Builds trim arguments (-ss, -to)
    func buildTrimArgs() -> [String] {
        guard trimEnabled else { return [] }
        var args: [String] = []
        let start = trimStart.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = trimEnd.trimmingCharacters(in: .whitespacesAndNewlines)
        if !start.isEmpty && start != "00:00:00" {
            args += ["-ss", start]
        }
        if !end.isEmpty {
            args += ["-to", end]
        }
        return args
    }

    /// Builds subtitle burn filter
    func buildSubtitleFilter() -> String? {
        guard burnSubtitles, !subtitleFilePath.isEmpty else { return nil }
        // Escape special characters in path for ffmpeg
        let escaped = subtitleFilePath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: ":", with: "\\:")
        return "subtitles='\(escaped)'"
    }

    /// Whether any processing option is enabled
    var hasProcessing: Bool {
        resolutionScale != .original ||
        trimEnabled ||
        (speedEnabled && speed != .x1) ||
        normalizeVolume ||
        noiseReduction ||
        deinterlace ||
        hdrToSdr ||
        colorCorrectionEnabled ||
        cropEnabled ||
        rotation != .none ||
        textOverlayEnabled ||
        fadeInEnabled ||
        fadeOutEnabled ||
        sharpenEnabled ||
        blurEnabled ||
        artisticEffect != .none ||
        burnSubtitles ||
        extractGif ||
        extractFrames
    }

    /// Builds the complete additional ffmpeg arguments
    func buildFfmpegArgs() -> [String] {
        var args: [String] = []

        // Trim args go before -i for seeking efficiency
        // Actually, for accuracy they go after -i
        args += buildTrimArgs()

        // Video filters
        var vFilters = buildVideoFilters()
        if let subFilter = buildSubtitleFilter() {
            vFilters.append(subFilter)
        }
        if !vFilters.isEmpty {
            args += ["-vf", vFilters.joined(separator: ",")]
        }

        // Audio filters
        let aFilters = buildAudioFilters()
        if !aFilters.isEmpty {
            args += ["-af", aFilters.joined(separator: ",")]
        }

        return args
    }
}
