//
//  ConversionView.swift
//  Youtube downloader
//

import SwiftUI
import UniformTypeIdentifiers

enum ConversionPreset: String, CaseIterable, Identifiable {
    case web = "Web MP4"
    case apple = "Apple"
    case audio = "Audio"
    case archive = "Archive"

    var id: String { rawValue }
}

struct ConversionView: View {
    var manager: DownloadManager
    var conversionManager: ConversionManager
    @Environment(LicenseManager.self) private var license
    @State private var selectedVideoCodec: VideoCodec = .h264
    @State private var selectedAudioCodec: AudioCodec = .aac
    @State private var selectedQuality: EncodingQuality = .medium
    @State private var selectedOutputFormat: String = "mp4"
    @State private var isDroppingFiles: Bool = false
    @State private var processingOptions = VideoProcessingOptions()
    @State private var showProcessingSheet: Bool = false
    @State private var audioOnlyExtraction: Bool = false
    @State private var showUpgradePrompt: Bool = false
    @State private var selectedPreset: ConversionPreset = .web

    private let outputFormats = ["mp4", "mkv", "mov", "webm", "avi", "ts", "flv", "wmv"]
    private let audioOutputFormats = ["mp3", "m4a", "flac", "wav", "ogg", "aac", "wma"]
    private let supportedTypes: [UTType] = {
        var types: [UTType] = [.movie, .audio, .mpeg4Movie, .quickTimeMovie, .avi, .mpeg, .mpeg2Video,
                               .mp3, .wav, .aiff]
        let extraExtensions = [
            // Video
            "mkv", "webm", "flv", "wmv", "m4v", "3gp", "mxf", "ts",
            "m2ts", "mts", "vob", "ogv", "divx", "asf", "rm", "rmvb",
            "3g2", "f4v", "dv",
            // Audio
            "m4a", "aac", "flac", "ogg", "wma", "opus", "alac", "ape",
            "wv", "ac3", "dts", "amr", "mka"
        ]
        for ext in extraExtensions {
            if let t = UTType(filenameExtension: ext) {
                types.append(t)
            }
        }
        return types
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Options bar
            optionsBar

            Divider()

            if conversionManager.items.isEmpty {
                dropZone
            } else {
                conversionList
            }
        }
        .sheet(isPresented: $showUpgradePrompt) {
            UpgradePromptView(reason: .featureLocked("Video Conversion"))
        }
        .onAppear {
            loadSavedPreset()
        }
    }

    // MARK: - Options Bar

    private var optionsBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("Video:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedVideoCodec) {
                    ForEach(VideoCodec.allCases) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            HStack(spacing: 6) {
                Text("Audio:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedAudioCodec) {
                    ForEach(AudioCodec.allCases) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            HStack(spacing: 6) {
                Text("Quality:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedQuality) {
                    ForEach(EncodingQuality.allCases) { q in
                        Text(q.rawValue).tag(q)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }

            HStack(spacing: 6) {
                Text("Output:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedOutputFormat) {
                    ForEach(audioOnlyExtraction ? audioOutputFormats : outputFormats, id: \.self) { f in
                        Text(f.uppercased()).tag(f)
                    }
                }
                .labelsHidden()
                .frame(width: 80)
                .onChange(of: audioOnlyExtraction) {
                    if audioOnlyExtraction {
                        selectedOutputFormat = "mp3"
                    } else {
                        selectedOutputFormat = "mp4"
                    }
                }
            }

            Divider().frame(height: 16)

            Toggle("Audio Only", isOn: $audioOnlyExtraction)
                .toggleStyle(.checkbox)
                .font(.callout)

            Divider().frame(height: 16)

            HStack(spacing: 6) {
                Text("Preset:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedPreset) {
                    ForEach(ConversionPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
                .onChange(of: selectedPreset) {
                    applyPreset(selectedPreset)
                }
            }

            Spacer()

            Button {
                if license.hasFullAccess {
                    showProcessingSheet = true
                } else {
                    showUpgradePrompt = true
                }
            } label: {
                HStack(spacing: 4) {
                    Label(processingOptions.hasProcessing ? "Processing (ON)" : "Processing",
                          systemImage: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .medium))
                    if !license.hasFullAccess {
                        Text("(Pro)")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .sheet(isPresented: $showProcessingSheet) {
                VideoProcessingView(options: processingOptions)
            }

            Button {
                if license.hasFullAccess {
                    openFilePicker()
                } else {
                    showUpgradePrompt = true
                }
            } label: {
                HStack(spacing: 4) {
                    Label("Add Files", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                    if !license.hasFullAccess {
                        Text("(Pro)")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                if license.hasFullAccess {
                    openConcatPicker()
                } else {
                    showUpgradePrompt = true
                }
            } label: {
                HStack(spacing: 4) {
                    Label("Concatenate", systemImage: "link")
                        .font(.system(size: 12, weight: .medium))
                    if !license.hasFullAccess {
                        Text("(Pro)")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("Join multiple video files into one")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Drop Zone

    private var dropZone: some View {
        VStack(spacing: 16) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundStyle(isDroppingFiles ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(maxWidth: 400, maxHeight: 200)

                VStack(spacing: 12) {
                    Image(systemName: isDroppingFiles ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 42))
                        .foregroundStyle(isDroppingFiles ? Color.accentColor : Color.secondary.opacity(0.4))

                    Text("Drop files here to convert")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Text("Or click \"Add Files\" above")
                        .font(.callout)
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDroppingFiles) { providers in
                handleFileDrop(providers: providers)
            }
            .accessibilityLabel("Drop zone for video files")
            .accessibilityHint("Drop video or audio files here to convert them")

            if !conversionManager.isFfmpegInstalled {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                        Text("ffmpeg is required for video conversion")
                            .font(.callout)
                    }
                    if manager.isInstallingFfmpeg {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(manager.installProgress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            manager.installFfmpeg()
                        } label: {
                            Label("Install ffmpeg", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
                .padding(16)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Conversion List

    private var conversionList: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(conversionManager.items.count) file\(conversionManager.items.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        summaryBadge("Running", value: conversionManager.convertingItemCount, tint: .orange)
                        summaryBadge("Waiting", value: conversionManager.waitingItemCount, tint: .secondary)
                        summaryBadge("Done", value: conversionManager.completedItemCount, tint: .green)
                        summaryBadge("Failed", value: conversionManager.failedItemCount, tint: .red)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    if conversionManager.failedItemCount > 0 {
                        Button("Retry Failed") {
                            conversionManager.retryFailedItems()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.orange)

                        Button("Remove Failed") {
                            conversionManager.removeFailedItems()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                    }

                    Button("Clear Finished") {
                        conversionManager.clearFinishedItems()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(conversionManager.items) { item in
                        ConversionRowView(item: item, manager: conversionManager)
                        Divider().padding(.leading, 16)
                    }
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDroppingFiles) { providers in
                handleFileDrop(providers: providers)
            }
        }
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = supportedTypes
        panel.prompt = "Add"
        panel.message = "Select video or audio files to convert."
        if panel.runModal() == .OK {
            conversionManager.addFiles(
                panel.urls,
                videoCodec: selectedVideoCodec,
                audioCodec: selectedAudioCodec,
                quality: selectedQuality,
                outputFormat: selectedOutputFormat,
                processingOptions: processingOptions,
                audioOnly: audioOnlyExtraction
            )
        }
    }

    private func openConcatPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = supportedTypes
        panel.prompt = "Concatenate"
        panel.message = "Select 2 or more video files to join together."
        if panel.runModal() == .OK, panel.urls.count >= 2 {
            conversionManager.concatenateFiles(panel.urls, outputFormat: selectedOutputFormat)
        }
    }

    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        guard license.hasFullAccess else { return false }

        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        urls.append(url)
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                conversionManager.addFiles(
                    urls,
                    videoCodec: selectedVideoCodec,
                    audioCodec: selectedAudioCodec,
                    quality: selectedQuality,
                    outputFormat: selectedOutputFormat,
                    processingOptions: processingOptions,
                    audioOnly: audioOnlyExtraction
                )
            }
        }
        return true
    }

    private func applyPreset(_ preset: ConversionPreset) {
        switch preset {
        case .web:
            audioOnlyExtraction = false
            selectedVideoCodec = .h264
            selectedAudioCodec = .aac
            selectedQuality = .medium
            selectedOutputFormat = "mp4"
        case .apple:
            audioOnlyExtraction = false
            selectedVideoCodec = .hevc
            selectedAudioCodec = .aac
            selectedQuality = .high
            selectedOutputFormat = "mov"
        case .audio:
            audioOnlyExtraction = true
            selectedAudioCodec = .aac
            selectedQuality = .medium
            selectedOutputFormat = "mp3"
        case .archive:
            audioOnlyExtraction = false
            selectedVideoCodec = .copy
            selectedAudioCodec = .copy
            selectedQuality = .high
            selectedOutputFormat = "mkv"
        }
        UserDefaults.standard.set(preset.rawValue, forKey: "conversionPreset")
    }

    private func loadSavedPreset() {
        if let raw = UserDefaults.standard.string(forKey: "conversionPreset"),
           let preset = ConversionPreset(rawValue: raw) {
            selectedPreset = preset
            applyPreset(preset)
        }
    }

    private func summaryBadge(_ label: String, value: Int, tint: Color) -> some View {
        Text("\(label) \(value)")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

// MARK: - Conversion Row View

struct ConversionRowView: View {
    var item: ConversionItem
    var manager: ConversionManager
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // File icon
            Image(systemName: "doc.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor.opacity(0.6))
                .frame(width: 40)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? item.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(item.fileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("→ \(item.outputFormat.uppercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(item.videoCodec.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Progress
                if case .converting(let progress) = item.status {
                    ProgressView(value: progress > 0 ? progress : nil)
                        .progressViewStyle(LinearProgressViewStyle())
                        .tint(Color.orange)
                        .frame(maxWidth: 400)
                }
                if case .failed(let msg) = item.status {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(Color.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Status + actions
            VStack(alignment: .trailing, spacing: 6) {
                statusBadge

                if isHovered || !item.status.isActive {
                    actionButtons
                }
            }
            .frame(width: 120)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .completed:
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.caption).fontWeight(.medium).foregroundStyle(Color.green)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .font(.caption).fontWeight(.medium).foregroundStyle(Color.red)
        case .cancelled:
            Label("Cancelled", systemImage: "minus.circle.fill")
                .font(.caption).foregroundStyle(Color.secondary)
        case .waiting:
            Label("Waiting", systemImage: "clock.fill")
                .font(.caption).foregroundStyle(Color.secondary)
        case .converting(let p):
            Label(p > 0 ? "\(Int(p * 100))%" : "Converting", systemImage: "gearshape.fill")
                .font(.caption).foregroundStyle(Color.orange)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if item.status.isActive {
                Button { manager.cancelConversion(item) } label: {
                    Image(systemName: "stop.circle").foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain).help("Cancel")
            }
            if case .completed = item.status {
                Button {
                    if let path = item.outputPath {
                        NSWorkspace.shared.activateFileViewerSelecting([path])
                    }
                } label: {
                    Image(systemName: "folder").foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain).help("Show in Finder")
            }
            if case .failed = item.status {
                Button { manager.retryConversion(item) } label: {
                    Image(systemName: "arrow.clockwise.circle").foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain).help("Retry")
            }
            Button { manager.removeItem(item) } label: {
                Image(systemName: "trash").foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain).help("Remove")
        }
    }
}
