//
//  DownloadRowView.swift
//  Youtube downloader
//

import SwiftUI

struct DownloadRowView: View {
    var item: DownloadItem
    var manager: DownloadManager

    @State private var isHovered = false
    @State private var showEditPopover = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            thumbnailView
                .frame(width: 80, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if item.isLiveStream {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .foregroundStyle(Color.primary)
                }

                HStack(spacing: 8) {
                    if let playlistTitle = item.playlistTitle {
                        HStack(spacing: 3) {
                            Image(systemName: "list.bullet")
                                .font(.caption2)
                            Text(playlistTitle)
                                .font(.caption)
                                .lineLimit(1)
                            if let idx = item.playlistIndex {
                                Text("#\(idx)")
                                    .font(.caption)
                            }
                        }
                        .foregroundStyle(Color.blue.opacity(0.8))
                    } else if !item.channelName.isEmpty {
                        Label(item.channelName, systemImage: "person.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !item.duration.isEmpty {
                        Label(item.duration, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Label(item.quality.rawValue, systemImage: "4k.tv")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(item.format.rawValue, systemImage: "film")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Progress
                progressView
            }

            Spacer()

            // Status + actions
            VStack(alignment: .trailing, spacing: 6) {
                statusBadge

                if isHovered || !item.status.isActive {
                    actionButtons
                }
            }
            .frame(width: 130)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: isHovered)
        .contextMenu { contextMenuItems }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), \(item.status.accessibilityDescription)")
        .accessibilityHint("Download item")
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        if let localThumb = item.localThumbnail {
            // Prefer locally extracted thumbnail
            AsyncImage(url: localThumb) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    thumbnailPlaceholder
                }
            }
        } else if let thumbURL = item.thumbnail {
            AsyncImage(url: thumbURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .empty:
                    thumbnailPlaceholder
                case .failure:
                    thumbnailPlaceholder
                @unknown default:
                    thumbnailPlaceholder
                }
            }
        } else {
            thumbnailPlaceholder
        }
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color(NSColor.controlBackgroundColor)
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.secondary.opacity(0.5))
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressView: some View {
        switch item.status {
        case .downloading(let progress, _, _):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(Color.blue)
                    .frame(maxWidth: 400)
                    .animation(reduceMotion ? nil : .linear(duration: 0.3), value: progress)
                HStack(spacing: 6) {
                    Text(item.status.displayText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if item.speedHistory.count >= 3 {
                        SpeedSparklineView(data: item.speedHistory)
                            .frame(width: 40, height: 12)
                    }
                }
            }
        case .processing(let progress):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: progress > 0 ? progress : nil)
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(Color.orange)
                    .frame(maxWidth: 400)
                    .animation(reduceMotion ? nil : .linear(duration: 0.3), value: progress)
                Text(progress > 0 ? "Converting… \(Int(progress * 100))%" : "Converting…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .fetchingInfo:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Fetching info…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .paused(let progress):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: min(max(progress, 0), 1))
                    .progressViewStyle(LinearProgressViewStyle())
                    .tint(Color.orange)
                    .frame(maxWidth: 400)
                    .animation(reduceMotion ? nil : .linear(duration: 0.3), value: progress)
                Text("Paused — \(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        case .failed(let msg):
            Text(msg)
                .font(.caption2)
                .foregroundStyle(Color.red)
                .lineLimit(2)
        default:
            EmptyView()
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .completed:
            if let warning = item.integrityWarning {
                Label("Warning", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.yellow)
                    .help(warning)
            } else {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.green)
            }
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Color.red)
        case .cancelled:
            Label("Cancelled", systemImage: "minus.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.secondary)
        case .waiting:
            Label("Waiting", systemImage: "clock.fill")
                .font(.caption)
                .foregroundStyle(Color.secondary)
        case .fetchingInfo:
            Label("Fetching", systemImage: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(Color.orange)
        case .processing(let progress):
            Label(progress > 0 ? "\(Int(progress * 100))%" : "Converting", systemImage: "gearshape.fill")
                .font(.caption)
                .foregroundStyle(Color.orange)
        case .downloading(let progress, _, _):
            Text("\(Int(progress * 100))%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.blue)
        case .paused(let progress):
            Label("\(Int(progress * 100))% paused", systemImage: "pause.circle.fill")
                .font(.caption)
                .foregroundStyle(Color.orange)
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if case .waiting = item.status {
                Button {
                    showEditPopover = true
                } label: {
                    Image(systemName: "pencil.circle")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Edit settings")
                .popover(isPresented: $showEditPopover) {
                    inlineEditPopover
                }
            }

            if case .downloading(let progress, _, _) = item.status {
                if progress > 10, item.outputPath != nil {
                    Button {
                        if let path = item.outputPath {
                            NSWorkspace.shared.open(path)
                        }
                    } label: {
                        Image(systemName: "eye.circle")
                            .foregroundStyle(Color.cyan)
                    }
                    .buttonStyle(.plain)
                    .help("Preview partial file")
                    .accessibilityLabel("Preview downloading file")
                }
                Button {
                    manager.pauseDownload(item)
                } label: {
                    Image(systemName: "pause.circle")
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)
                .help("Pause")
                .accessibilityLabel("Pause download")
            }

            if case .paused = item.status {
                Button {
                    manager.resumeDownload(item)
                } label: {
                    Image(systemName: "play.circle")
                        .foregroundStyle(Color.green)
                }
                .buttonStyle(.plain)
                .help("Resume")
                .accessibilityLabel("Resume download")
            }

            if item.status.isActive {
                Button {
                    manager.cancelDownload(item)
                } label: {
                    Image(systemName: "stop.circle")
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel")
                .accessibilityLabel("Cancel download")
            }

            if case .completed = item.status {
                Button {
                    manager.openInFinder(item)
                } label: {
                    Image(systemName: "folder")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
                .accessibilityLabel("Show in Finder")
            }

            if case .failed = item.status {
                Button {
                    manager.retryDownload(item)
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(.plain)
                .help("Retry")
                .accessibilityLabel("Retry download")
            }

            Button {
                manager.removeItem(item)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove")
            .accessibilityLabel("Remove from queue")
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if item.status.isActive {
            Button("Cancel") { manager.cancelDownload(item) }
        }
        if case .failed = item.status {
            Button("Retry") { manager.retryDownload(item) }
        }
        if case .completed = item.status {
            Button("Show in Finder") { manager.openInFinder(item) }
        }
        if case .waiting = item.status {
            Button("Edit Settings") { showEditPopover = true }
        }

        Divider()

        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url, forType: .string)
        }

        Divider()

        Button("Remove", role: .destructive) { manager.removeItem(item) }
    }

    // MARK: - Inline Edit Popover

    private var inlineEditPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Download Settings")
                .font(.headline)

            HStack {
                Text("Quality")
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: Binding(
                    get: { item.quality },
                    set: { item.quality = $0 }
                )) {
                    ForEach(VideoQuality.allCases) { q in
                        Text(q.rawValue).tag(q)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            HStack {
                Text("Format")
                    .frame(width: 60, alignment: .leading)
                Picker("", selection: Binding(
                    get: { item.format },
                    set: { item.format = $0 }
                )) {
                    ForEach(OutputFormat.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }

            Toggle("Subtitles", isOn: Binding(
                get: { item.subtitles },
                set: { item.subtitles = $0 }
            ))
            .toggleStyle(.checkbox)
        }
        .padding(16)
        .frame(width: 260)
    }
}

// MARK: - Speed Sparkline

struct SpeedSparklineView: View {
    let data: [Double]

    var body: some View {
        Canvas { context, size in
            guard data.count >= 2 else { return }
            let maxVal = data.max() ?? 1
            guard maxVal > 0 else { return }
            let stepX = size.width / CGFloat(data.count - 1)

            var path = Path()
            for (i, val) in data.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height - (CGFloat(val / maxVal) * size.height)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(.blue.opacity(0.6)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
