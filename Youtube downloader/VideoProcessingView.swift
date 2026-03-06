//
//  VideoProcessingView.swift
//  Youtube downloader
//

import SwiftUI
import UniformTypeIdentifiers

struct VideoProcessingView: View {
    @Bindable var options: VideoProcessingOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Video Processing")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Resolution
                    processingSection(title: "Resolution", icon: "arrow.up.left.and.arrow.down.right") {
                        Picker("Scale to:", selection: $options.resolutionScale) {
                            ForEach(ResolutionScale.allCases) { r in
                                Text(r.rawValue).tag(r)
                            }
                        }
                        .frame(width: 250)
                    }

                    // Trim
                    processingSection(title: "Trim / Clip", icon: "scissors") {
                        Toggle("Enable trimming", isOn: $options.trimEnabled)
                            .toggleStyle(.checkbox)
                        if options.trimEnabled {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading) {
                                    Text("Start").font(.caption).foregroundStyle(.secondary)
                                    TextField("00:00:00", text: $options.trimStart)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 100)
                                }
                                VStack(alignment: .leading) {
                                    Text("End").font(.caption).foregroundStyle(.secondary)
                                    TextField("00:05:00", text: $options.trimEnd)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 100)
                                }
                            }
                            Text("Use HH:MM:SS format. Leave End empty for end of video.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Speed
                    processingSection(title: "Speed", icon: "gauge.with.dots.needle.50percent") {
                        Toggle("Change speed", isOn: $options.speedEnabled)
                            .toggleStyle(.checkbox)
                        if options.speedEnabled {
                            Picker("Speed:", selection: $options.speed) {
                                ForEach(SpeedMultiplier.allCases) { s in
                                    Text(s.rawValue).tag(s)
                                }
                            }
                            .frame(width: 200)
                        }
                    }

                    // Audio Processing
                    processingSection(title: "Audio Processing", icon: "waveform") {
                        Toggle("Normalize volume (loudnorm)", isOn: $options.normalizeVolume)
                            .toggleStyle(.checkbox)
                        Toggle("Noise reduction", isOn: $options.noiseReduction)
                            .toggleStyle(.checkbox)
                    }

                    // Color Correction
                    processingSection(title: "Color Correction", icon: "paintpalette") {
                        Toggle("Enable color correction", isOn: $options.colorCorrectionEnabled)
                            .toggleStyle(.checkbox)
                        if options.colorCorrectionEnabled {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Brightness")
                                        .font(.callout)
                                        .frame(width: 80, alignment: .leading)
                                    Slider(value: $options.brightness, in: -1.0...1.0, step: 0.05)
                                        .frame(width: 200)
                                    Text(String(format: "%.2f", options.brightness))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40)
                                }
                                HStack {
                                    Text("Contrast")
                                        .font(.callout)
                                        .frame(width: 80, alignment: .leading)
                                    Slider(value: $options.contrast, in: 0.0...3.0, step: 0.05)
                                        .frame(width: 200)
                                    Text(String(format: "%.2f", options.contrast))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40)
                                }
                                HStack {
                                    Text("Saturation")
                                        .font(.callout)
                                        .frame(width: 80, alignment: .leading)
                                    Slider(value: $options.saturation, in: 0.0...3.0, step: 0.05)
                                        .frame(width: 200)
                                    Text(String(format: "%.2f", options.saturation))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40)
                                }
                                Button("Reset") {
                                    options.brightness = 0.0
                                    options.contrast = 1.0
                                    options.saturation = 1.0
                                }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                            }
                        }
                    }

                    // Crop
                    processingSection(title: "Crop", icon: "crop") {
                        Toggle("Enable crop", isOn: $options.cropEnabled)
                            .toggleStyle(.checkbox)
                        if options.cropEnabled {
                            Picker("Preset:", selection: $options.cropPreset) {
                                ForEach(CropPreset.allCases) { p in
                                    Text(p.rawValue).tag(p)
                                }
                            }
                            .frame(width: 250)

                            if options.cropPreset == .custom {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading) {
                                        Text("Width").font(.caption).foregroundStyle(.secondary)
                                        TextField("pixels", text: $options.cropWidth)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                    }
                                    VStack(alignment: .leading) {
                                        Text("Height").font(.caption).foregroundStyle(.secondary)
                                        TextField("pixels", text: $options.cropHeight)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                    }
                                    VStack(alignment: .leading) {
                                        Text("X offset").font(.caption).foregroundStyle(.secondary)
                                        TextField("center", text: $options.cropX)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                    }
                                    VStack(alignment: .leading) {
                                        Text("Y offset").font(.caption).foregroundStyle(.secondary)
                                        TextField("center", text: $options.cropY)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                    }
                                }
                                Text("Leave offset empty to center the crop")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Rotation & Flip
                    processingSection(title: "Rotation & Flip", icon: "rotate.right") {
                        Picker("Transform:", selection: $options.rotation) {
                            ForEach(RotationOption.allCases) { r in
                                Text(r.rawValue).tag(r)
                            }
                        }
                        .frame(width: 250)
                    }

                    // Text Overlay
                    processingSection(title: "Text Overlay", icon: "textformat") {
                        Toggle("Enable text overlay", isOn: $options.textOverlayEnabled)
                            .toggleStyle(.checkbox)
                        if options.textOverlayEnabled {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading) {
                                    Text("Text").font(.caption).foregroundStyle(.secondary)
                                    TextField("Your text here", text: $options.overlayText)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 200)
                                }
                                VStack(alignment: .leading) {
                                    Text("Position").font(.caption).foregroundStyle(.secondary)
                                    Picker("", selection: $options.textPosition) {
                                        Text("Top").tag("top")
                                        Text("Center").tag("center")
                                        Text("Bottom").tag("bottom")
                                    }
                                    .labelsHidden()
                                    .frame(width: 90)
                                }
                            }
                            HStack(spacing: 12) {
                                VStack(alignment: .leading) {
                                    Text("Font Size").font(.caption).foregroundStyle(.secondary)
                                    TextField("24", value: $options.textFontSize, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 60)
                                }
                                VStack(alignment: .leading) {
                                    Text("Color").font(.caption).foregroundStyle(.secondary)
                                    Picker("", selection: $options.textColor) {
                                        Text("White").tag("white")
                                        Text("Black").tag("black")
                                        Text("Yellow").tag("yellow")
                                        Text("Red").tag("red")
                                        Text("Green").tag("green")
                                        Text("Blue").tag("blue")
                                    }
                                    .labelsHidden()
                                    .frame(width: 90)
                                }
                            }
                        }
                    }

                    // Fade In/Out
                    processingSection(title: "Fade Effects", icon: "circle.lefthalf.filled") {
                        HStack(spacing: 20) {
                            VStack(alignment: .leading) {
                                Toggle("Fade in", isOn: $options.fadeInEnabled)
                                    .toggleStyle(.checkbox)
                                if options.fadeInEnabled {
                                    HStack {
                                        Text("Duration:")
                                            .font(.callout)
                                        TextField("1.0", value: $options.fadeInDuration, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                        Text("sec")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            VStack(alignment: .leading) {
                                Toggle("Fade out", isOn: $options.fadeOutEnabled)
                                    .toggleStyle(.checkbox)
                                if options.fadeOutEnabled {
                                    HStack {
                                        Text("Duration:")
                                            .font(.callout)
                                        TextField("1.0", value: $options.fadeOutDuration, format: .number)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                        Text("sec")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if options.fadeOutEnabled {
                            Text("Fade-out requires video duration info (available for conversions)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Sharpen / Blur
                    processingSection(title: "Sharpen / Blur", icon: "sparkles") {
                        Toggle("Sharpen", isOn: $options.sharpenEnabled)
                            .toggleStyle(.checkbox)
                        if options.sharpenEnabled {
                            HStack {
                                Text("Strength")
                                    .font(.callout)
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: $options.sharpenStrength, in: 0.0...3.0, step: 0.1)
                                    .frame(width: 200)
                                Text(String(format: "%.1f", options.sharpenStrength))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40)
                            }
                        }
                        Toggle("Blur", isOn: $options.blurEnabled)
                            .toggleStyle(.checkbox)
                        if options.blurEnabled {
                            HStack {
                                Text("Radius")
                                    .font(.callout)
                                    .frame(width: 80, alignment: .leading)
                                Slider(value: Binding(
                                    get: { Double(options.blurStrength) },
                                    set: { options.blurStrength = Int($0) }
                                ), in: 1...10, step: 1)
                                    .frame(width: 200)
                                Text("\(options.blurStrength)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40)
                            }
                        }
                    }

                    // Artistic Effects
                    processingSection(title: "Artistic Effects", icon: "paintbrush") {
                        Picker("Effect:", selection: $options.artisticEffect) {
                            ForEach(ArtisticEffect.allCases) { e in
                                Text(e.rawValue).tag(e)
                            }
                        }
                        .frame(width: 250)
                    }

                    // Video Processing
                    processingSection(title: "Video Processing", icon: "film") {
                        Toggle("Deinterlace (yadif)", isOn: $options.deinterlace)
                            .toggleStyle(.checkbox)
                        Toggle("HDR to SDR tonemapping", isOn: $options.hdrToSdr)
                            .toggleStyle(.checkbox)
                    }

                    // Subtitle Burn
                    processingSection(title: "Burn Subtitles", icon: "captions.bubble") {
                        Toggle("Burn subtitles into video", isOn: $options.burnSubtitles)
                            .toggleStyle(.checkbox)
                        if options.burnSubtitles {
                            HStack {
                                TextField("Subtitle file path (.srt, .ass)", text: $options.subtitleFilePath)
                                    .textFieldStyle(.roundedBorder)
                                Button("Browse") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.allowsMultipleSelection = false
                                    panel.allowedContentTypes = [
                                        UTType(filenameExtension: "srt") ?? .plainText,
                                        UTType(filenameExtension: "ass") ?? .plainText,
                                        UTType(filenameExtension: "vtt") ?? .plainText
                                    ]
                                    if panel.runModal() == .OK, let url = panel.url {
                                        options.subtitleFilePath = url.path
                                    }
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                        }
                    }

                    // GIF Extraction
                    processingSection(title: "GIF Extraction", icon: "photo.on.rectangle") {
                        Toggle("Extract as GIF", isOn: $options.extractGif)
                            .toggleStyle(.checkbox)
                        if options.extractGif {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading) {
                                    Text("Start").font(.caption).foregroundStyle(.secondary)
                                    TextField("00:00:00", text: $options.gifStart)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 100)
                                }
                                VStack(alignment: .leading) {
                                    Text("Duration (sec)").font(.caption).foregroundStyle(.secondary)
                                    TextField("5", text: $options.gifDuration)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 60)
                                }
                                VStack(alignment: .leading) {
                                    Text("Width (px)").font(.caption).foregroundStyle(.secondary)
                                    TextField("480", value: $options.gifWidth, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 60)
                                }
                            }
                        }
                    }

                    // Frame Extraction
                    processingSection(title: "Frame Extraction", icon: "photo") {
                        Toggle("Extract frames as images", isOn: $options.extractFrames)
                            .toggleStyle(.checkbox)
                        if options.extractFrames {
                            HStack {
                                Text("Number of frames:")
                                    .font(.callout)
                                TextField("1", value: $options.frameCount, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                if options.hasProcessing {
                    Text("Processing options enabled")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
        }
        .frame(width: 480, height: 600)
    }

    private func processingSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
    }
}
