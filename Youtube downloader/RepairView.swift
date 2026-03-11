//
//  RepairView.swift
//  Youtube downloader
//

import SwiftUI
import UniformTypeIdentifiers

struct RepairView: View {
    var manager: DownloadManager
    var repairManager: RepairManager
    @Environment(LicenseManager.self) private var license
    @State private var isDroppingFiles: Bool = false
    @State private var showUpgradePrompt: Bool = false

    private let supportedExtensions = [
        // Video
        "mp4", "mov", "m4v", "mkv", "avi", "3gp", "mxf", "webm", "ts",
        "flv", "wmv", "mpg", "mpeg", "vob", "ogv", "divx", "asf",
        "rm", "rmvb", "3g2", "mts", "m2ts", "f4v", "swf", "dv", "gif",
        // Audio
        "mp3", "m4a", "aac", "flac", "wav", "ogg", "wma", "opus",
        "aiff", "aif", "alac", "ape", "wv", "ac3", "dts", "amr", "mka"
    ]

    private static let supportedContentTypes: [UTType] = {
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

            if repairManager.items.isEmpty {
                dropZone
            } else {
                repairList
            }
        }
        .sheet(isPresented: $showUpgradePrompt) {
            UpgradePromptView(reason: .featureLocked("Video Repair"))
        }
    }

    // MARK: - Options Bar

    private var optionsBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text("Mode:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Picker("", selection: Bindable(repairManager).repairMode) {
                    ForEach(RepairMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                .help(repairManager.repairMode.description)
            }

            Divider().frame(height: 16)

            // Scan All button
            Button {
                repairManager.scanAllItems()
            } label: {
                Label("Scan All", systemImage: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(repairManager.items.isEmpty)

            // Repair All button
            Button {
                repairManager.repairAllScanned()
            } label: {
                Label("Repair All", systemImage: "wrench.and.screwdriver.fill")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!hasRepairableItems)

            Spacer()

            Button {
                openFilePicker()
            } label: {
                Label("Add Files", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var hasRepairableItems: Bool {
        repairManager.items.contains { item in
            if case .scanned(let severity) = item.status, severity != "None" {
                return true
            }
            return false
        }
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
                    Image(systemName: isDroppingFiles ? "arrow.down.circle.fill" : "wrench.and.screwdriver.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(isDroppingFiles ? Color.accentColor : Color.secondary.opacity(0.4))

                    Text("Drop corrupted videos here")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Text("Scan and repair damaged MP4, MOV, MKV, AVI, and more")
                        .font(.callout)
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isDroppingFiles) { providers in
                handleFileDrop(providers: providers)
            }
            .accessibilityLabel("Drop zone for corrupted video files")
            .accessibilityHint("Drop video files here to scan and repair them")

            if !repairManager.isFfmpegInstalled {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                        Text("ffmpeg is required for video repair")
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

    // MARK: - Repair List

    private var repairList: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("\(repairManager.items.count) file\(repairManager.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Clear Completed") {
                    repairManager.clearCompleted()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(repairManager.items) { item in
                        RepairRowView(item: item, manager: repairManager)
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
        panel.allowedContentTypes = Self.supportedContentTypes
        panel.prompt = "Add"
        panel.message = "Select video files to scan and repair."
        if panel.runModal() == .OK {
            repairManager.addFiles(panel.urls)
        }
    }

    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        let ext = url.pathExtension.lowercased()
                        if supportedExtensions.contains(ext) {
                            urls.append(url)
                        }
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            if !urls.isEmpty {
                repairManager.addFiles(urls)
            }
        }
        return true
    }
}

// MARK: - Repair Row View

struct RepairRowView: View {
    var item: RepairItem
    var manager: RepairManager
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // File icon with severity color
            fileIcon

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(item.fileSizeString)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !item.resolution.isEmpty {
                        Text(item.resolution)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if !item.codec.isEmpty {
                        Text(item.codec.uppercased())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Issues summary
                issuesSummary

                // Progress
                progressView
            }

            Spacer()

            // Status + actions
            VStack(alignment: .trailing, spacing: 6) {
                statusBadge

                if isHovered || !item.isActive {
                    actionButtons
                }
            }
            .frame(width: 140)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .onHover { isHovered = $0 }
    }

    // MARK: - File Icon

    private var fileIcon: some View {
        ZStack {
            Image(systemName: "doc.fill")
                .font(.system(size: 24))
                .foregroundStyle(iconColor.opacity(0.6))
        }
        .frame(width: 40)
    }

    private var iconColor: Color {
        switch item.severityColor {
        case "green": return .green
        case "yellow": return .yellow
        case "orange": return .orange
        case "red": return .red
        default: return .accentColor
        }
    }

    // MARK: - Issues Summary

    @ViewBuilder
    private var issuesSummary: some View {
        if case .scanned(let severity) = item.status {
            if severity == "None" {
                Text("No issues detected")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else if !item.detectedIssues.isEmpty {
                Text(item.detectedIssues.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        if case .failed(let msg) = item.status {
            Text(msg)
                .font(.caption2)
                .foregroundStyle(Color.red)
                .lineLimit(2)
        }
        if case .completed = item.status {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("Repaired successfully — Stage \(item.repairStage)")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressView: some View {
        if case .repairing(let progress, let stage, let totalStages) = item.status {
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: progress > 0 ? progress : nil)
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(Color.orange)
                    .frame(maxWidth: 400)

                Text("Stage \(stage)/\(totalStages): \(stageName(stage))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        if case .scanning = item.status {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning for damage…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stageName(_ stage: Int) -> String {
        switch stage {
        case 1: return "Container Rebuild"
        case 2: return "Faststart Fix"
        case 3: return "Error-Tolerant Remux"
        case 4: return "Discard Corrupt Frames"
        case 5: return "Audio Resync"
        case 6: return "Full Re-encode"
        default: return "Repairing"
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .waiting:
            Label("Waiting", systemImage: "clock.fill")
                .font(.caption).foregroundStyle(Color.secondary)
        case .scanning:
            Label("Scanning", systemImage: "magnifyingglass")
                .font(.caption).foregroundStyle(Color.blue)
        case .scanned(let severity):
            severityBadge(severity)
        case .repairing(let p, _, _):
            Label(p > 0 ? "\(Int(p * 100))%" : "Repairing", systemImage: "wrench.fill")
                .font(.caption).fontWeight(.medium).foregroundStyle(Color.orange)
        case .completed:
            Label("Repaired", systemImage: "checkmark.circle.fill")
                .font(.caption).fontWeight(.medium).foregroundStyle(Color.green)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .font(.caption).fontWeight(.medium).foregroundStyle(Color.red)
        case .cancelled:
            Label("Cancelled", systemImage: "minus.circle.fill")
                .font(.caption).foregroundStyle(Color.secondary)
        }
    }

    @ViewBuilder
    private func severityBadge(_ severity: String) -> some View {
        let color: Color = switch severity {
        case "None": .green
        case "Minor": .yellow
        case "Moderate": .orange
        case "Severe", "Critical": .red
        default: .gray
        }

        Text(severity == "None" ? "Healthy" : severity)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if case .scanned(let severity) = item.status, severity != "None" {
                Button { manager.startRepair(item) } label: {
                    Image(systemName: "wrench.fill").foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain).help("Repair")
            }
            if item.isActive {
                Button { manager.cancelRepair(item) } label: {
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
                Button { manager.retryRepair(item) } label: {
                    Image(systemName: "arrow.clockwise.circle").foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain).help("Retry")
            }
            if case .scanned = item.status {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.repairReport, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain).help("Copy repair report")
            }
            Button { manager.removeItem(item) } label: {
                Image(systemName: "trash").foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain).help("Remove")
        }
    }
}
