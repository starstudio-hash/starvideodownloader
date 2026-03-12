//
//  ContentView.swift
//  Youtube downloader
//

import SwiftUI
import UniformTypeIdentifiers

enum AppTab: String, CaseIterable {
    case downloads = "Downloads"
    case convert = "Convert"
    case repair = "Repair"
    case history = "History"
    case stats = "Stats"

    var icon: String {
        switch self {
        case .downloads: return "arrow.down.circle.fill"
        case .convert:   return "arrow.triangle.2.circlepath"
        case .repair:    return "wrench.and.screwdriver.fill"
        case .history:   return "clock.fill"
        case .stats:     return "chart.bar.fill"
        }
    }
}

enum StatusFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case completed = "Completed"
    case failed = "Failed"
}

enum QueueSortOption: String, CaseIterable, Identifiable {
    case manual = "Manual"
    case newest = "Newest"
    case oldest = "Oldest"
    case status = "Status"
    case playlist = "Playlist"

    var id: String { rawValue }
}

struct ContentView: View {
    @Environment(DownloadManager.self) private var manager
    @Environment(LicenseManager.self) private var license
    @State private var urlInput: String = ""
    @State private var selectedQuality: VideoQuality = .best1080
    @State private var selectedFormat: OutputFormat = .mp4
    @State private var downloadSubtitles: Bool = false
    @State private var downloadPlaylist: Bool = false
    @State private var showSettings: Bool = false
    @State private var showBatchInput: Bool = false
    @State private var showInvalidURLAlert: Bool = false
    @State private var showInstallAlert: Bool = false
    @State private var showDuplicateAlert: Bool = false
    @State private var duplicateAlertMessage: String = ""
    @State private var duplicateAlertAllowsOverride: Bool = false
    @State private var pendingDuplicateURL: String? = nil
    @State private var pendingDuplicateIsPlaylist: Bool = false
    @State private var isDroppingURL: Bool = false
    @State private var showUpgradePrompt: Bool = false
    @State private var upgradeReason: UpgradeReason = .dailyLimitReached
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Tab navigation
    @State private var selectedTab: AppTab = .downloads
    // Search & filter
    @State private var searchText: String = ""
    @State private var statusFilter: StatusFilter = .all
    @State private var sortOption: QueueSortOption = .manual
    // Playlist confirmation
    @State private var pendingPlaylistURL: String? = nil
    @State private var pendingPlaylistItemCount: Int = 0
    @State private var pendingPlaylistTitle: String? = nil
    @State private var pendingPlaylistEntries: [PlaylistEntryPreview] = []
    @State private var selectedPlaylistEntryIDs: Set<String> = []
    @State private var showPlaylistConfirm: Bool = false
    @State private var isInspectingPlaylist: Bool = false
    @State private var showPlaylistInspectError: Bool = false
    @State private var playlistInspectErrorMessage: String = ""
    @State private var urlInspection: URLInspectionResult? = nil
    @State private var isInspectingURL: Bool = false
    @State private var urlInspectionErrorMessage: String = ""
    @State private var previewWorkItem: DispatchWorkItem?

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            headerBar

            Divider()

            // Tab bar
            tabBar

            Divider()

            // Tab content
            switch selectedTab {
            case .downloads:
                downloadsContent
            case .convert:
                ZStack {
                    ConversionView(manager: manager, conversionManager: manager.conversionManager)
                    if !license.hasFullAccess {
                        ProFeatureOverlay(featureName: "Video Conversion")
                    }
                }
            case .repair:
                ZStack {
                    RepairView(manager: manager, repairManager: manager.repairManager)
                    if !license.hasFullAccess {
                        ProFeatureOverlay(featureName: "Video Repair")
                    }
                }
            case .history:
                HistoryView(manager: manager)
            case .stats:
                StatsView(manager: manager)
                    .onAppear { manager.startBandwidthSampling() }
                    .onDisappear { manager.stopBandwidthSampling() }
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showSettings) {
            SettingsView(manager: manager, settings: manager.settings)
        }
        .sheet(isPresented: $showBatchInput) {
            BatchURLInputView(manager: manager)
        }
        .sheet(isPresented: $showPlaylistConfirm, onDismiss: { clearPendingPlaylistSelection() }) {
            PlaylistSelectionView(
                playlistTitle: pendingPlaylistTitle ?? "Playlist",
                entries: pendingPlaylistEntries,
                selectedIDs: $selectedPlaylistEntryIDs,
                onCancel: { clearPendingPlaylistSelection() },
                onConfirm: {
                    if let url = pendingPlaylistURL {
                        let selectedEntries = pendingPlaylistEntries.filter { selectedPlaylistEntryIDs.contains($0.id) }
                        startPlaylistDownload(url: url, selectedEntries: selectedEntries)
                    }
                    clearPendingPlaylistSelection()
                }
            )
        }
        .sheet(isPresented: $showUpgradePrompt) {
            UpgradePromptView(reason: upgradeReason)
        }
        .alert("Invalid URL", isPresented: $showInvalidURLAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please enter a valid video URL.\n\nSupported: YouTube, Vimeo, Twitter/X, TikTok, Instagram, Reddit, Dailymotion, and 1000+ other sites.")
        }
        .alert("yt-dlp Not Installed", isPresented: $showInstallAlert) {
            Button("Install Now") {
                manager.installYtdlp()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("yt-dlp is required to download videos.\n\nTap \"Install Now\" to download and install it automatically.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .pasteAndDownload)) { _ in
            if let str = NSPasteboard.general.string(forType: .string) {
                urlInput = str.trimmingCharacters(in: .whitespacesAndNewlines)
                submitDownload()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showBatchInput)) { _ in
            if license.hasFullAccess {
                showBatchInput = true
            } else {
                upgradeReason = .batchDisabled
                showUpgradePrompt = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearCompleted)) { _ in
            manager.clearCompleted()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchTab)) { notification in
            if let tab = notification.object as? AppTab {
                selectedTab = tab
            }
        }
        .alert("Duplicate URL", isPresented: $showDuplicateAlert) {
            if duplicateAlertAllowsOverride {
                Button("Add Anyway") {
                    forceSubmitDuplicate()
                }
            }
            Button(duplicateAlertAllowsOverride ? "Cancel" : "OK", role: .cancel) {
                clearPendingDuplicate()
            }
        } message: {
            Text(duplicateAlertMessage)
        }
        .alert("Playlist Inspection Failed", isPresented: $showPlaylistInspectError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playlistInspectErrorMessage)
        }
        .onChange(of: urlInput) {
            scheduleURLInspection()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HeaderBarView(
            activeCount: activeDownloadCount,
            hasFullAccess: license.hasFullAccess,
            dailyDownloadsRemaining: license.dailyDownloadsRemaining,
            hasActiveDownloads: manager.hasActiveDownloads,
            hasPausedItems: manager.hasPausedItems,
            totalBandwidth: manager.totalBandwidth,
            onSettingsTapped: { showSettings = true },
            onPauseAll: { manager.pauseAll() },
            onResumeAll: { manager.resumeAll() }
        )
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        TabBarView(selectedTab: $selectedTab)
    }

    // MARK: - Downloads Content

    private var downloadsContent: some View {
        VStack(spacing: 0) {
            // URL input area
            urlInputArea

            if shouldShowURLInspectionCard {
                urlInspectionCard
            }

            // Setup banner when yt-dlp is not installed
            if !manager.isYtdlpInstalled {
                setupBanner
            }

            if let summary = manager.backendHealthSummary, manager.isYtdlpInstalled {
                backendHealthBanner(summary: summary)
            }

            Divider()

            // Downloads list
            if manager.items.isEmpty {
                emptyState
            } else {
                downloadsList
            }
        }
    }

    private var setupBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Setup Required")
                    .font(.callout.bold())
                Text("Install yt-dlp to start downloading videos. It's free and takes one click.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if manager.isInstallingYtdlp {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(manager.installProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    manager.installYtdlp()
                } label: {
                    Text("Install")
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.06))
    }

    private func backendHealthBanner(summary: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: manager.hasBackendErrors ? "exclamationmark.triangle.fill" : "wrench.and.screwdriver.fill")
                .foregroundStyle(manager.hasBackendErrors ? Color.orange : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(manager.hasBackendErrors ? "Action Needed" : "Backend Check")
                    .font(.callout.bold())
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") {
                manager.refreshBackendHealth(checkVersions: true)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
    }

    // MARK: - URL Input

    private var urlInputArea: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // URL field with drag-and-drop support
                HStack(spacing: 6) {
                    Image(systemName: isDroppingURL ? "arrow.down.circle" : detectedSiteIcon)
                        .foregroundStyle(isDroppingURL ? Color.accentColor : detectedSiteColor)
                        .font(.system(size: 13))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isDroppingURL)
                    if let siteName = detectedSiteName {
                        Text(siteName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(detectedSiteColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(detectedSiteColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    TextField("Paste video URL (YouTube, Vimeo, Twitter, 1000+ sites)…", text: $urlInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit { submitDownload() }
                        .accessibilityLabel("Video URL input")
                        .accessibilityHint("Enter a video URL to download")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isDroppingURL ? Color.accentColor.opacity(0.08) : Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isDroppingURL ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: isDroppingURL ? 2 : 1)
                )
                .onDrop(of: [UTType.url, UTType.plainText], isTargeted: $isDroppingURL) { providers in
                    handleDrop(providers: providers)
                }

                // Paste button
                Button {
                    if let str = NSPasteboard.general.string(forType: .string) {
                        urlInput = str
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(SecondaryButtonStyle())

                // Batch URL button
                Button {
                    if license.hasFullAccess {
                        showBatchInput = true
                    } else {
                        upgradeReason = .batchDisabled
                        showUpgradePrompt = true
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 12))
                        if !license.hasFullAccess {
                            Text("(Pro)")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .help(license.hasFullAccess ? "Batch URL input" : "Pro feature: Batch URL input")

                // Download button
                Button {
                    submitDownload()
                } label: {
                    if isInspectingPlaylist {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Inspecting…")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    } else {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isInspectingPlaylist)
            }

            // Options row
            HStack(spacing: 16) {
                // Quality picker
                HStack(spacing: 6) {
                    Image(systemName: "4k.tv")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Picker("Quality", selection: $selectedQuality) {
                        ForEach(VideoQuality.allCases) { q in
                            if !license.hasFullAccess && license.isProOnly(q) {
                                Text("\(q.rawValue) (Pro)").tag(q)
                            } else {
                                Text(q.rawValue).tag(q)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                    .onChange(of: selectedQuality) {
                        if !license.hasFullAccess && license.isProOnly(selectedQuality) {
                            selectedQuality = .best1080
                            upgradeReason = .qualityRestricted
                            showUpgradePrompt = true
                        }
                    }
                    .onChange(of: license.hasFullAccess) {
                        if !license.hasFullAccess && license.isProOnly(selectedQuality) {
                            selectedQuality = .best1080
                        }
                    }
                }

                // Format picker
                HStack(spacing: 6) {
                    Image(systemName: "film")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(OutputFormat.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }

                Divider().frame(height: 16)

                // Subtitles toggle
                Toggle(isOn: $downloadSubtitles) {
                    HStack(spacing: 4) {
                        Image(systemName: "captions.bubble")
                            .font(.system(size: 11))
                        Text("Subtitles")
                            .font(.system(size: 12))
                    }
                }
                .toggleStyle(.checkbox)

                // Playlist toggle
                Toggle(isOn: $downloadPlaylist) {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 11))
                        Text("Playlist")
                            .font(.system(size: 12))
                        if !license.hasFullAccess {
                            Text("(Pro)")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .toggleStyle(.checkbox)
                .disabled(!license.hasFullAccess)
                .onTapGesture {
                    if !license.hasFullAccess {
                        upgradeReason = .playlistDisabled
                        showUpgradePrompt = true
                    }
                }

                Spacer()

                // Daily download counter for free users
                if !license.hasFullAccess {
                    Text("\(license.dailyDownloadsRemaining) downloads left today")
                        .font(.caption)
                        .foregroundStyle(license.dailyDownloadsRemaining <= 1 ? .red : .secondary)
                }

                if isInspectingPlaylist {
                    Text("Inspecting playlist…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Output: \(manager.settings.outputDirectory.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var shouldShowURLInspectionCard: Bool {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return manager.isYtdlpInstalled && !trimmed.isEmpty && (isInspectingURL || urlInspection != nil || !urlInspectionErrorMessage.isEmpty)
    }

    private var urlInspectionCard: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let thumbnailURL = urlInspection?.thumbnailURL {
                        AsyncImage(url: thumbnailURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.12))
                                .overlay { ProgressView().controlSize(.small) }
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.12))
                            .overlay {
                                Image(systemName: urlInspection?.isPlaylist == true ? "list.bullet.rectangle" : detectedSiteIcon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 72, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
                    if isInspectingURL {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Inspecting URL…")
                                .font(.callout.weight(.medium))
                        }
                        Text("Fetching title, channel, duration, and playlist details before you add it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let inspection = urlInspection {
                        Text(inspection.playlistTitle ?? inspection.title ?? "Detected media")
                            .font(.callout.weight(.medium))
                            .lineLimit(2)

                        HStack(spacing: 10) {
                            if let channel = inspection.channel, !channel.isEmpty {
                                Label(channel, systemImage: "person.circle")
                            }
                            if let durationText = inspection.durationText, !durationText.isEmpty {
                                Label(durationText, systemImage: "clock")
                            }
                            if inspection.isLiveStream {
                                Label("Live", systemImage: "dot.radiowaves.left.and.right")
                                    .foregroundStyle(.red)
                            }
                            if inspection.isPlaylist {
                                Label("\(inspection.playlistCount) videos", systemImage: "list.bullet")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if inspection.isPlaylist, !inspection.playlistEntries.isEmpty {
                            Text(inspection.playlistEntries.prefix(3).map { "\($0.index). \($0.title)" }.joined(separator: "  •  "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    } else if !urlInspectionErrorMessage.isEmpty {
                        Text(urlInspectionErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 52))
                .foregroundStyle(Color.secondary.opacity(0.4))

            Text("No downloads yet")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text("Paste a video URL above and click Download.\nSupports YouTube, Vimeo, Twitter/X, TikTok, Instagram, and 1000+ other sites.")
                .font(.callout)
                .foregroundStyle(Color.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if !manager.isYtdlpInstalled {
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.orange)
                        Text("yt-dlp is required to download videos")
                            .font(.callout)
                    }
                    if manager.isInstallingYtdlp {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(manager.installProgress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Button {
                            manager.installYtdlp()
                        } label: {
                            Label("Install yt-dlp", systemImage: "arrow.down.circle.fill")
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

    /// Cached active count — avoids redundant O(n) filter in headerBar
    private var activeDownloadCount: Int {
        manager.items.reduce(0) { $0 + ($1.status.isActive ? 1 : 0) }
    }

    // MARK: - Downloads List

    private var filteredItems: [DownloadItem] {
        var items = manager.items

        // Apply status filter
        switch statusFilter {
        case .all: break
        case .active:
            items = items.filter { $0.status.isActive }
        case .completed:
            items = items.filter { if case .completed = $0.status { return true }; return false }
        case .failed:
            items = items.filter { if case .failed = $0.status { return true }; return false }
        }

        // Apply search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            items = items.filter {
                $0.title.lowercased().contains(query) ||
                $0.url.lowercased().contains(query) ||
                $0.channelName.lowercased().contains(query)
            }
        }

        switch sortOption {
        case .manual:
            break
        case .newest:
            items.sort { $0.addedDate > $1.addedDate }
        case .oldest:
            items.sort { $0.addedDate < $1.addedDate }
        case .status:
            items.sort { statusRank($0.status) < statusRank($1.status) }
        case .playlist:
            items.sort {
                let lhsTitle = $0.playlistTitle ?? "~"
                let rhsTitle = $1.playlistTitle ?? "~"
                if lhsTitle == rhsTitle {
                    return ($0.playlistIndex ?? Int.max, $0.addedDate) < ($1.playlistIndex ?? Int.max, $1.addedDate)
                }
                return lhsTitle < rhsTitle
            }
        }

        return items
    }

    private var downloadsList: some View {
        let currentFiltered = filteredItems
        let totalCount = manager.items.count
        return VStack(spacing: 0) {
            // Toolbar row with search and filter
            HStack(spacing: 10) {
                // Search field
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Search…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .frame(width: 160)

                Picker("Sort", selection: $sortOption) {
                    ForEach(QueueSortOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 110)

                // Status filter
                ForEach(StatusFilter.allCases, id: \.self) { filter in
                    Button {
                        statusFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(statusFilter == filter ? Color.accentColor.opacity(0.15) : Color.clear)
                            .foregroundStyle(statusFilter == filter ? Color.accentColor : .secondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("\(currentFiltered.count) of \(totalCount) item\(totalCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if manager.items.contains(where: { if case .failed = $0.status { return true }; return false }) {
                    Button("Retry Failed") {
                        manager.retryFailedDownloads()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)

                    Button("Remove Failed") {
                        manager.removeFailedDownloads()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Clear Completed") {
                    manager.clearCompleted()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)

                Text("·")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Clear All") {
                    manager.clearAllDownloads()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.secondary)

                Text("·")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Export") {
                    exportQueue()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)

                Button("Import") {
                    importQueue()
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
                    ForEach(currentFiltered) { item in
                        DownloadRowView(item: item, manager: manager)
                            .draggable(item.id.uuidString) {
                                // Drag preview
                                Text(item.title)
                                    .padding(8)
                                    .background(.ultraThinMaterial)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .dropDestination(for: String.self) { droppedItems, _ in
                                guard let sourceIDString = droppedItems.first,
                                      let sourceID = UUID(uuidString: sourceIDString) else {
                                    return false
                                }
                                manager.moveItem(from: sourceID, to: item.id)
                                return true
                            }
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    // MARK: - Site Detection

    private var detectedSiteHost: String? {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else { return nil }
        return host
    }

    private var detectedSiteName: String? {
        guard let host = detectedSiteHost else { return nil }
        if host.contains("youtube.com") || host.contains("youtu.be") { return "YouTube" }
        if host.contains("vimeo.com") { return "Vimeo" }
        if host.contains("twitter.com") || host.contains("x.com") { return "X" }
        if host.contains("tiktok.com") { return "TikTok" }
        if host.contains("instagram.com") { return "Instagram" }
        if host.contains("reddit.com") { return "Reddit" }
        if host.contains("dailymotion.com") { return "Dailymotion" }
        if host.contains("twitch.tv") { return "Twitch" }
        if host.contains("soundcloud.com") { return "SoundCloud" }
        if host.contains("facebook.com") || host.contains("fb.watch") { return "Facebook" }
        return nil
    }

    private var detectedSiteIcon: String {
        guard let host = detectedSiteHost else { return "link" }
        if host.contains("youtube.com") || host.contains("youtu.be") { return "play.rectangle.fill" }
        if host.contains("vimeo.com") { return "video.fill" }
        if host.contains("twitter.com") || host.contains("x.com") { return "bubble.left.fill" }
        if host.contains("tiktok.com") { return "music.note" }
        if host.contains("instagram.com") { return "camera.fill" }
        if host.contains("reddit.com") { return "text.bubble.fill" }
        if host.contains("twitch.tv") { return "gamecontroller.fill" }
        if host.contains("soundcloud.com") { return "waveform" }
        if host.contains("facebook.com") || host.contains("fb.watch") { return "person.2.fill" }
        return "link"
    }

    private var detectedSiteColor: Color {
        guard let host = detectedSiteHost else { return .secondary }
        if host.contains("youtube.com") || host.contains("youtu.be") { return .red }
        if host.contains("vimeo.com") { return .cyan }
        if host.contains("twitter.com") || host.contains("x.com") { return .blue }
        if host.contains("tiktok.com") { return .pink }
        if host.contains("instagram.com") { return .purple }
        if host.contains("reddit.com") { return .orange }
        if host.contains("twitch.tv") { return .purple }
        if host.contains("soundcloud.com") { return .orange }
        if host.contains("facebook.com") || host.contains("fb.watch") { return .blue }
        return .secondary
    }

    private func submitDownload() {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard isValidDownloadURL(trimmed) else {
            showInvalidURLAlert = true
            return
        }

        guard manager.isYtdlpInstalled else {
            showInstallAlert = true
            return
        }

        // License check: daily download limit
        if !license.canDownload {
            upgradeReason = .dailyLimitReached
            showUpgradePrompt = true
            return
        }

        // Auto-detect playlist URLs (contain list= param), or use the toggle
        let isPlaylistURL = trimmed.contains("list=") || trimmed.contains("/playlist?")
        if downloadPlaylist || isPlaylistURL {
            if !license.hasFullAccess {
                upgradeReason = .playlistDisabled
                showUpgradePrompt = true
                return
            }
            if handleDuplicateIfNeeded(url: trimmed, isPlaylist: true) { return }
            inspectPlaylist(url: trimmed)
        } else {
            if handleDuplicateIfNeeded(url: trimmed, isPlaylist: false) { return }
            manager.addDownload(
                url: trimmed,
                quality: selectedQuality,
                format: selectedFormat,
                subtitles: downloadSubtitles,
                playlistDownload: false
            )
            urlInput = ""
        }
    }

    private func startPlaylistDownload(url: String, selectedEntries: [PlaylistEntryPreview]) {
        manager.addPlaylistDownload(
            url: url,
            quality: selectedQuality,
            format: selectedFormat,
            subtitles: downloadSubtitles,
            selectedEntries: selectedEntries
        )
        urlInput = ""
    }

    private func inspectPlaylist(url: String) {
        isInspectingPlaylist = true
        pendingPlaylistURL = url
        pendingPlaylistItemCount = 0
        pendingPlaylistTitle = nil
        manager.inspectPlaylist(url: url) { result in
            isInspectingPlaylist = false
            switch result {
            case .success(let inspection):
                pendingPlaylistItemCount = inspection.playlistCount
                pendingPlaylistTitle = inspection.playlistTitle ?? inspection.title
                pendingPlaylistEntries = inspection.playlistEntries.sorted { $0.index < $1.index }
                selectedPlaylistEntryIDs = Set(inspection.playlistEntries.map(\.id))
                showPlaylistConfirm = true
            case .failure(let error):
                playlistInspectErrorMessage = error.errorDescription ?? "Could not inspect that playlist."
                showPlaylistInspectError = true
            }
        }
    }

    private func clearPendingPlaylistSelection() {
        pendingPlaylistURL = nil
        pendingPlaylistTitle = nil
        pendingPlaylistItemCount = 0
        pendingPlaylistEntries = []
        selectedPlaylistEntryIDs = []
    }

    private func handleDuplicateIfNeeded(url: String, isPlaylist: Bool) -> Bool {
        guard let message = manager.duplicateMessage(for: url) else { return false }

        switch manager.settings.duplicateHandling {
        case .allow:
            return false
        case .skip:
            duplicateAlertMessage = message + " It was skipped because duplicate handling is set to Skip."
            duplicateAlertAllowsOverride = false
            showDuplicateAlert = true
            return true
        case .ask:
            pendingDuplicateURL = url
            pendingDuplicateIsPlaylist = isPlaylist
            duplicateAlertMessage = message + " Do you want to add it anyway?"
            duplicateAlertAllowsOverride = true
            showDuplicateAlert = true
            return true
        }
    }

    private func forceSubmitDuplicate() {
        guard let url = pendingDuplicateURL else { return }
        let isPlaylist = pendingDuplicateIsPlaylist
        clearPendingDuplicate()
        if isPlaylist {
            inspectPlaylist(url: url)
        } else {
            manager.addDownload(
                url: url,
                quality: selectedQuality,
                format: selectedFormat,
                subtitles: downloadSubtitles,
                playlistDownload: false
            )
            urlInput = ""
        }
    }

    private func scheduleURLInspection() {
        previewWorkItem?.cancel()
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isValidDownloadURL(trimmed), manager.isYtdlpInstalled else {
            isInspectingURL = false
            urlInspection = nil
            urlInspectionErrorMessage = ""
            return
        }

        isInspectingURL = true
        urlInspectionErrorMessage = ""

        let requestedURL = trimmed
        let work = DispatchWorkItem {
            manager.inspectURL(url: requestedURL) { result in
                guard requestedURL == urlInput.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                isInspectingURL = false
                switch result {
                case .success(let inspection):
                    urlInspection = inspection
                    urlInspectionErrorMessage = ""
                case .failure(let error):
                    urlInspection = nil
                    urlInspectionErrorMessage = error.errorDescription ?? "Could not inspect that URL."
                }
            }
        }
        previewWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func clearPendingDuplicate() {
        pendingDuplicateURL = nil
        pendingDuplicateIsPlaylist = false
        duplicateAlertAllowsOverride = false
    }

    private func statusRank(_ status: DownloadStatus) -> Int {
        switch status {
        case .failed:
            return 0
        case .downloading, .processing, .fetchingInfo:
            return 1
        case .paused:
            return 2
        case .waiting:
            return 3
        case .completed:
            return 4
        case .cancelled:
            return 5
        }
    }

    private func isValidDownloadURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host, host.contains(".")
        else { return false }
        return true
    }

    // MARK: - Import/Export

    private func exportQueue() {
        guard let data = manager.exportQueue() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "download-queue.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func importQueue() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            manager.importQueue(from: data)
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                DispatchQueue.main.async {
                    if let url = item as? URL {
                        self.urlInput = url.absoluteString
                    } else if let data = item as? Data, let urlStr = String(data: data, encoding: .utf8) {
                        self.urlInput = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            return true
        }
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                DispatchQueue.main.async {
                    if let str = item as? String {
                        self.urlInput = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    } else if let data = item as? Data, let str = String(data: data, encoding: .utf8) {
                        self.urlInput = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            return true
        }
        return false
    }
}

// MARK: - Extracted Subviews

struct HeaderBarView: View {
    let activeCount: Int
    let hasFullAccess: Bool
    let dailyDownloadsRemaining: Int
    let hasActiveDownloads: Bool
    let hasPausedItems: Bool
    let totalBandwidth: String?
    let onSettingsTapped: () -> Void
    let onPauseAll: () -> Void
    let onResumeAll: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.red)
                Text("Star Video Downloader")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            tierBadge

            Spacer()

            if activeCount > 0 {
                Label("\(activeCount) active", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.15))
                    .foregroundStyle(Color.blue)
                    .clipShape(Capsule())
            }

            if let bandwidth = totalBandwidth {
                Text(bandwidth)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .foregroundStyle(Color.green)
                    .clipShape(Capsule())
            }

            if hasActiveDownloads {
                Button {
                    onPauseAll()
                } label: {
                    Image(systemName: "pause.circle")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help("Pause All")
                .accessibilityLabel("Pause all downloads")
            }

            if hasPausedItems {
                Button {
                    onResumeAll()
                } label: {
                    Image(systemName: "play.circle")
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .help("Resume All")
                .accessibilityLabel("Resume all downloads")
            }

            Button {
                onSettingsTapped()
            } label: {
                Image(systemName: "gear")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var tierBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: hasFullAccess ? "checkmark.seal.fill" : "person.crop.circle.badge.questionmark")
                .font(.system(size: 11))
            Text(hasFullAccess ? "Pro" : "Free")
                .font(.caption.weight(.semibold))
            if !hasFullAccess {
                Text("· \(dailyDownloadsRemaining) left today")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background((hasFullAccess ? Color.blue : Color.secondary).opacity(0.12))
        .foregroundStyle(hasFullAccess ? Color.blue : Color.secondary)
        .clipShape(Capsule())
        .help(hasFullAccess ? "Pro license active" : "Free tier active")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            hasFullAccess
            ? "Pro license active"
            : "Free tier active, \(dailyDownloadsRemaining) downloads left today"
        )
    }
}

struct TabBarView: View {
    @Binding var selectedTab: AppTab
    @Environment(LicenseManager.self) private var license

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12))
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: .medium))
                        if (tab == .convert || tab == .repair) && !license.hasFullAccess {
                            Text("(Pro)")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.12) : Color.clear)
                    .foregroundStyle(selectedTab == tab ? Color.accentColor : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct PlaylistSelectionView: View {
    let playlistTitle: String
    let entries: [PlaylistEntryPreview]
    @Binding var selectedIDs: Set<String>
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlistTitle)
                        .font(.title3.weight(.semibold))
                    Text("Choose which videos to add to your queue.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    selectedIDs = Set(entries.map(\.id))
                } label: {
                    Text("Select All")
                }
                .buttonStyle(.plain)

                Button {
                    selectedIDs.removeAll()
                } label: {
                    Text("Clear")
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        Button {
                            if selectedIDs.contains(entry.id) {
                                selectedIDs.remove(entry.id)
                            } else {
                                selectedIDs.insert(entry.id)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: selectedIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(entry.id) ? Color.accentColor : .secondary)
                                    .font(.system(size: 16))
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(entry.index). \(entry.title)")
                                        .font(.callout)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)

                                    HStack(spacing: 8) {
                                        if let channel = entry.channel, !channel.isEmpty {
                                            Label(channel, systemImage: "person.circle")
                                        }
                                        if let durationText = entry.durationText, !durationText.isEmpty {
                                            Label(durationText, systemImage: "clock")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())

                Spacer()

                Button("Add \(selectedIDs.count) to Queue") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedIDs.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 620, height: 520)
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Color.red.opacity(0.8) : Color.red)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? Color(NSColor.controlBackgroundColor).opacity(0.7) : Color(NSColor.controlBackgroundColor))
            .foregroundStyle(Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
    }
}

#Preview {
    ContentView()
        .environment(DownloadManager(settings: SettingsManager()))
        .environment(LicenseManager())
}
