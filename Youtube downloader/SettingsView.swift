//
//  SettingsView.swift
//  Youtube downloader
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var manager: DownloadManager
    @Bindable var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss
    @Environment(LicenseManager.self) private var license
    @State private var licenseKeyInput: String = ""
    @State private var showLicenseError: Bool = false
    @State private var licenseErrorMessage: String = ""
    @State private var showUpgradePrompt: Bool = false
    @State private var upgradeReason: UpgradeReason = .featureLocked("")

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
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
                VStack(alignment: .leading, spacing: 24) {

                    // License
                    settingsSection(title: "License", icon: "key.fill") {
                        VStack(alignment: .leading, spacing: 10) {
                            // Status badge
                            HStack(spacing: 8) {
                                if license.isPro {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.green)
                                    Text("Pro License Active")
                                        .fontWeight(.medium)
                                } else {
                                    Image(systemName: "lock.fill")
                                        .foregroundStyle(.secondary)
                                    Text("Free Plan")
                                        .fontWeight(.medium)
                                }
                            }

                            if license.isPro {
                                HStack {
                                    Text(maskedKey(license.licenseKey))
                                        .font(.system(.callout, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Deactivate") {
                                        Task { await license.deactivateLicense() }
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                    .controlSize(.small)
                                }
                            } else {
                                HStack(spacing: 8) {
                                    TextField("Enter your license key", text: $licenseKeyInput)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(width: 240)
                                        .onSubmit { activateKey() }
                                    Button("Activate") { activateKey() }
                                        .buttonStyle(PrimaryButtonStyle())
                                        .controlSize(.small)
                                        .disabled(licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || license.isActivating)
                                    if license.isActivating {
                                        ProgressView()
                                            .controlSize(.small)
                                    }
                                }
                                if showLicenseError {
                                    Text(licenseErrorMessage)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }

                                Button("Buy Pro License — $5") {
                                    NSWorkspace.shared.open(UpgradePromptView.purchaseURL)
                                }
                                .buttonStyle(.plain)
                                .font(.callout)
                                .foregroundStyle(Color.accentColor)
                            }

                            if !license.hasFullAccess {
                                Text("Free: \(license.dailyDownloadsRemaining)/\(LicenseManager.freeDailyDownloadLimit) downloads remaining today")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Download Defaults
                    settingsSection(title: "Download Defaults", icon: "arrow.down.circle") {
                        VStack(alignment: .leading, spacing: 12) {
                            settingsRow(label: "Default Quality") {
                                Picker("", selection: $settings.defaultQuality) {
                                    ForEach(VideoQuality.allCases) { q in
                                        if !license.hasFullAccess && license.isProOnly(q) {
                                            Text("\(q.rawValue) (Pro)").tag(q)
                                        } else {
                                            Text(q.rawValue).tag(q)
                                        }
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 200)
                                .onChange(of: settings.defaultQuality) {
                                    if !license.hasFullAccess && license.isProOnly(settings.defaultQuality) {
                                        settings.defaultQuality = .best1080
                                        upgradeReason = .qualityRestricted
                                        showUpgradePrompt = true
                                    } else {
                                        settings.saveSettings()
                                    }
                                }
                                .onChange(of: license.hasFullAccess) {
                                    if !license.hasFullAccess && license.isProOnly(settings.defaultQuality) {
                                        settings.defaultQuality = .best1080
                                        settings.saveSettings()
                                    }
                                }
                            }

                            settingsRow(label: "Default Format") {
                                Picker("", selection: $settings.defaultFormat) {
                                    ForEach(OutputFormat.allCases) { f in
                                        Text(f.rawValue).tag(f)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 120)
                                .onChange(of: settings.defaultFormat) { settings.saveSettings() }
                            }

                            settingsRow(label: "Simultaneous") {
                                if license.hasFullAccess {
                                    Picker("", selection: $settings.maxConcurrentDownloads) {
                                        ForEach(1...10, id: \.self) { n in
                                            Text("\(n)").tag(n)
                                        }
                                        Text("Unlimited").tag(0)
                                    }
                                    .labelsHidden()
                                    .frame(width: 100)
                                    .onChange(of: settings.maxConcurrentDownloads) { settings.saveSettings() }
                                    Text("downloads at once")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("1")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    Text("downloads at once")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                    Text("(Pro)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .onTapGesture {
                                            upgradeReason = .featureLocked("Simultaneous Downloads")
                                            showUpgradePrompt = true
                                        }
                                }
                            }

                            settingsRow(label: "Download Subtitles") {
                                Toggle("", isOn: $settings.downloadSubtitlesByDefault)
                                    .labelsHidden()
                                    .onChange(of: settings.downloadSubtitlesByDefault) { settings.saveSettings() }
                            }

                            settingsRow(label: "Mac Compatible") {
                                Toggle("", isOn: $settings.macCompatibleEncoding)
                                    .labelsHidden()
                                    .onChange(of: settings.macCompatibleEncoding) { settings.saveSettings() }
                            }
                            if settings.macCompatibleEncoding {
                                Text("Re-encodes to H.264 + AAC so files preview with the Space bar in Finder.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.leading, 164)

                                settingsRow(label: "Encode Quality") {
                                    Picker("", selection: $settings.encodingQuality) {
                                        ForEach(EncodingQuality.allCases) { q in
                                            Text(q.rawValue).tag(q)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 120)
                                    .onChange(of: settings.encodingQuality) { settings.saveSettings() }
                                }
                                Text(settings.encodingQuality.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 164)

                                settingsRow(label: "Video Codec") {
                                    Picker("", selection: $settings.selectedVideoCodec) {
                                        ForEach(VideoCodec.allCases) { c in
                                            Text(c.rawValue).tag(c)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 180)
                                    .onChange(of: settings.selectedVideoCodec) { settings.saveSettings() }
                                }
                                if let note = settings.selectedVideoCodec.availabilityNote {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .padding(.leading, 164)
                                }

                                settingsRow(label: "Audio Codec") {
                                    Picker("", selection: $settings.selectedAudioCodec) {
                                        ForEach(AudioCodec.allCases) { c in
                                            Text(c.rawValue).tag(c)
                                        }
                                    }
                                    .labelsHidden()
                                    .frame(width: 180)
                                    .onChange(of: settings.selectedAudioCodec) { settings.saveSettings() }
                                }
                            }
                        }
                    }

                    // yt-dlp Options
                    settingsSection(title: "yt-dlp Options", icon: "terminal.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            settingsRow(label: "Browser Cookies") {
                                Picker("", selection: $settings.cookiesFromBrowser) {
                                    Text("None").tag("none")
                                    Text("Chrome").tag("chrome")
                                    Text("Safari").tag("safari")
                                    Text("Firefox").tag("firefox")
                                }
                                .labelsHidden()
                                .frame(width: 120)
                                .onChange(of: settings.cookiesFromBrowser) { settings.saveSettings() }
                            }
                            Text("Use browser cookies for age-restricted or private videos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 164)

                            settingsRow(label: "Rate Limit") {
                                Toggle("", isOn: $settings.rateLimitEnabled)
                                    .labelsHidden()
                                    .onChange(of: settings.rateLimitEnabled) { settings.saveSettings() }
                                if settings.rateLimitEnabled {
                                    Picker("", selection: $settings.rateLimitSpeed) {
                                        Text("1 MB/s").tag("1M")
                                        Text("2 MB/s").tag("2M")
                                        Text("5 MB/s").tag("5M")
                                        Text("10 MB/s").tag("10M")
                                        Text("20 MB/s").tag("20M")
                                    }
                                    .labelsHidden()
                                    .frame(width: 100)
                                    .onChange(of: settings.rateLimitSpeed) { settings.saveSettings() }
                                }
                            }
                            if settings.rateLimitEnabled {
                                Text("Cap download bandwidth to avoid saturating your connection")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 164)
                            }

                            settingsRow(label: "Download Archive") {
                                Toggle("", isOn: $settings.useDownloadArchive)
                                    .labelsHidden()
                                    .onChange(of: settings.useDownloadArchive) { settings.saveSettings() }
                                Text("Skip already-downloaded videos")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            settingsRow(label: "SponsorBlock") {
                                Toggle("", isOn: $settings.sponsorBlockEnabled)
                                    .labelsHidden()
                                    .disabled(!license.hasFullAccess)
                                    .onChange(of: settings.sponsorBlockEnabled) { settings.saveSettings() }
                                if settings.sponsorBlockEnabled && license.hasFullAccess {
                                    Picker("", selection: $settings.sponsorBlockMode) {
                                        Text("All segments").tag("all")
                                        Text("Sponsors only").tag("sponsor")
                                    }
                                    .labelsHidden()
                                    .frame(width: 140)
                                    .onChange(of: settings.sponsorBlockMode) { settings.saveSettings() }
                                }
                                if !license.hasFullAccess {
                                    Text("(Pro)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .onTapGesture {
                                            upgradeReason = .featureLocked("SponsorBlock")
                                            showUpgradePrompt = true
                                        }
                                }
                            }

                            settingsRow(label: "Embed Thumbnail") {
                                Toggle("", isOn: $settings.embedThumbnail)
                                    .labelsHidden()
                                    .onChange(of: settings.embedThumbnail) { settings.saveSettings() }
                            }

                            settingsRow(label: "Embed Metadata") {
                                Toggle("", isOn: $settings.embedMetadata)
                                    .labelsHidden()
                                    .onChange(of: settings.embedMetadata) { settings.saveSettings() }
                            }

                            settingsRow(label: "Embed Chapters") {
                                Toggle("", isOn: $settings.embedChapters)
                                    .labelsHidden()
                                    .disabled(!license.hasFullAccess)
                                    .onChange(of: settings.embedChapters) { settings.saveSettings() }
                                if !license.hasFullAccess {
                                    Text("(Pro)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .onTapGesture {
                                            upgradeReason = .featureLocked("Embed Chapters")
                                            showUpgradePrompt = true
                                        }
                                }
                            }

                            settingsRow(label: "Split Chapters") {
                                Toggle("", isOn: $settings.splitChapters)
                                    .labelsHidden()
                                    .onChange(of: settings.splitChapters) { settings.saveSettings() }
                            }
                            if settings.splitChapters {
                                Text("Split long videos into separate files per chapter")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 164)
                            }

                            settingsRow(label: "Geo Bypass") {
                                Toggle("", isOn: $settings.geoBypass)
                                    .labelsHidden()
                                    .onChange(of: settings.geoBypass) { settings.saveSettings() }
                                if settings.geoBypass {
                                    TextField("Country code", text: $settings.geoBypassCountry)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                        .onChange(of: settings.geoBypassCountry) { settings.saveSettings() }
                                }
                            }

                            settingsRow(label: "Fragments") {
                                Picker("", selection: $settings.concurrentFragments) {
                                    ForEach(1...8, id: \.self) { n in
                                        Text("\(n)").tag(n)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 70)
                                .onChange(of: settings.concurrentFragments) { settings.saveSettings() }
                                Text("concurrent fragments")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            settingsRow(label: "Playlist Items") {
                                TextField("e.g. 1-5,8,10", text: $settings.playlistItemsFilter)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 150)
                                    .onChange(of: settings.playlistItemsFilter) { settings.saveSettings() }
                            }

                            settingsRow(label: "Match Filter") {
                                TextField("e.g. duration>60", text: $settings.matchFilter)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 150)
                                    .onChange(of: settings.matchFilter) { settings.saveSettings() }
                            }

                            Divider().padding(.vertical, 4)

                            settingsRow(label: "Live: From Start") {
                                Toggle("", isOn: $settings.liveFromStart)
                                    .labelsHidden()
                                    .onChange(of: settings.liveFromStart) { settings.saveSettings() }
                                Text("Record from beginning")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            settingsRow(label: "Live: Wait") {
                                Toggle("", isOn: $settings.waitForVideo)
                                    .labelsHidden()
                                    .onChange(of: settings.waitForVideo) { settings.saveSettings() }
                                Text("Wait for scheduled streams")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            Divider().padding(.vertical, 4)

                            settingsRow(label: "Sleep Interval") {
                                Toggle("", isOn: $settings.sleepIntervalEnabled)
                                    .labelsHidden()
                                    .disabled(!license.hasFullAccess)
                                    .onChange(of: settings.sleepIntervalEnabled) { settings.saveSettings() }
                                if settings.sleepIntervalEnabled && license.hasFullAccess {
                                    Stepper("\(settings.sleepIntervalMin)s min", value: $settings.sleepIntervalMin, in: 0...60)
                                        .frame(width: 110)
                                        .onChange(of: settings.sleepIntervalMin) { settings.saveSettings() }
                                    Stepper("\(settings.sleepIntervalMax)s max", value: $settings.sleepIntervalMax, in: 0...120)
                                        .frame(width: 110)
                                        .onChange(of: settings.sleepIntervalMax) { settings.saveSettings() }
                                }
                                if !license.hasFullAccess {
                                    Text("(Pro)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .onTapGesture {
                                            upgradeReason = .featureLocked("Sleep Interval")
                                            showUpgradePrompt = true
                                        }
                                }
                            }
                            if settings.sleepIntervalEnabled {
                                Text("Random delay between batch downloads to avoid rate limiting")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 164)
                            }

                            settingsRow(label: "Format Sort") {
                                TextField("e.g. res,ext:mp4:m4a", text: $settings.formatSortString)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                                    .disabled(!license.hasFullAccess)
                                    .onChange(of: settings.formatSortString) { settings.saveSettings() }
                                if !license.hasFullAccess {
                                    Text("(Pro)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .onTapGesture {
                                            upgradeReason = .featureLocked("Format Sort")
                                            showUpgradePrompt = true
                                        }
                                }
                            }
                            if !settings.formatSortString.isEmpty {
                                Text("yt-dlp -S flag: prefer AV1, HDR, higher framerate, etc.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 164)
                            }

                            settingsRow(label: "Embed Subtitles") {
                                Toggle("", isOn: $settings.embedSubtitles)
                                    .labelsHidden()
                                    .disabled(!license.hasFullAccess)
                                    .onChange(of: settings.embedSubtitles) { settings.saveSettings() }
                                Text("Embed subs into video container")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                if !license.hasFullAccess {
                                    Text("(Pro)")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .onTapGesture {
                                            upgradeReason = .featureLocked("Embed Subtitles")
                                            showUpgradePrompt = true
                                        }
                                }
                            }

                            settingsRow(label: "File Conflicts") {
                                Picker("", selection: $settings.fileConflictBehavior) {
                                    Text("Rename").tag("rename")
                                    Text("Overwrite").tag("overwrite")
                                    Text("Skip").tag("skip")
                                }
                                .labelsHidden()
                                .frame(width: 120)
                                .onChange(of: settings.fileConflictBehavior) { settings.saveSettings() }
                            }

                            if settings.embedThumbnail {
                                settingsRow(label: "Thumbnail Format") {
                                    Picker("", selection: $settings.convertThumbnailsFormat) {
                                        Text("Default").tag("")
                                        Text("JPG").tag("jpg")
                                        Text("PNG").tag("png")
                                    }
                                    .labelsHidden()
                                    .frame(width: 100)
                                    .onChange(of: settings.convertThumbnailsFormat) { settings.saveSettings() }
                                    Text("Convert embedded thumbnails")
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            settingsRow(label: "Cookies File") {
                                HStack(spacing: 6) {
                                    TextField("Path to cookies.txt", text: $settings.cookiesFilePath)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 200)
                                        .onChange(of: settings.cookiesFilePath) { settings.saveSettings() }
                                    Button("Browse…") {
                                        let panel = NSOpenPanel()
                                        panel.canChooseFiles = true
                                        panel.canChooseDirectories = false
                                        panel.allowedContentTypes = [.plainText]
                                        panel.message = "Select a cookies.txt file"
                                        if panel.runModal() == .OK, let url = panel.url {
                                            settings.cookiesFilePath = url.path
                                            settings.saveSettings()
                                        }
                                    }
                                    .buttonStyle(SecondaryButtonStyle())
                                    .controlSize(.small)
                                }
                            }
                            if !settings.cookiesFilePath.isEmpty {
                                Text("Netscape-format cookies file for site authentication")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 164)
                            }
                        }
                    }

                    // Advanced
                    settingsSection(title: "Advanced", icon: "gearshape.2") {
                        VStack(alignment: .leading, spacing: 12) {
                            settingsRow(label: "Scheduled Downloads") {
                                Toggle("", isOn: $settings.scheduledDownloadEnabled)
                                    .labelsHidden()
                                    .onChange(of: settings.scheduledDownloadEnabled) {
                                        settings.saveSettings()
                                        manager.setupScheduler()
                                    }
                                if settings.scheduledDownloadEnabled {
                                    DatePicker("", selection: $settings.scheduledDownloadTime, displayedComponents: .hourAndMinute)
                                        .labelsHidden()
                                        .frame(width: 90)
                                        .onChange(of: settings.scheduledDownloadTime) {
                                            settings.saveSettings()
                                            manager.setupScheduler()
                                        }
                                }
                            }
                            if settings.scheduledDownloadEnabled {
                                Text("Waiting downloads will start at this time daily")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 164)
                            }

                            settingsRow(label: "After Download") {
                                Picker("", selection: $settings.postDownloadAction) {
                                    Text("Do Nothing").tag("none")
                                    Text("Open File").tag("open")
                                    Text("Reveal in Finder").tag("reveal")
                                    Text("Run Script").tag("script")
                                }
                                .labelsHidden()
                                .frame(width: 150)
                                .onChange(of: settings.postDownloadAction) { settings.saveSettings() }
                            }
                            if settings.postDownloadAction == "script" {
                                settingsRow(label: "Script") {
                                    TextField("e.g. /usr/local/bin/process {file}", text: $settings.postDownloadScript)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 250)
                                        .onChange(of: settings.postDownloadScript) { settings.saveSettings() }
                                }
                                Text("Use {file} as placeholder for the downloaded file path")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 164)
                            }
                        }
                    }

                    // macOS Integration
                    settingsSection(title: "macOS Integration", icon: "desktopcomputer") {
                        VStack(alignment: .leading, spacing: 12) {
                            settingsRow(label: "Notifications") {
                                Toggle("", isOn: $settings.notificationsEnabled)
                                    .labelsHidden()
                                    .onChange(of: settings.notificationsEnabled) { settings.saveSettings() }
                                Text("Show when downloads complete or fail")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            settingsRow(label: "Clipboard Monitor") {
                                Toggle("", isOn: $settings.clipboardMonitoring)
                                    .labelsHidden()
                                    .onChange(of: settings.clipboardMonitoring) {
                                        settings.saveSettings()
                                        if settings.clipboardMonitoring {
                                            manager.startClipboardMonitoring()
                                        } else {
                                            manager.stopClipboardMonitoring()
                                        }
                                    }
                                Text("Detect video URLs copied to clipboard")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }

                            settingsRow(label: "Launch at Login") {
                                Toggle("", isOn: $settings.launchAtLogin)
                                    .labelsHidden()
                                    .onChange(of: settings.launchAtLogin) {
                                        settings.saveSettings()
                                        manager.updateLoginItem()
                                    }
                            }
                        }
                    }

                    // Filename & Organization
                    settingsSection(title: "Filename & Organization", icon: "doc.text") {
                        VStack(alignment: .leading, spacing: 12) {
                            settingsRow(label: "Filename Template") {
                                TextField("%(title)s.%(ext)s", text: $settings.filenameTemplate)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 250)
                                    .onChange(of: settings.filenameTemplate) { settings.saveSettings() }
                            }
                            Text("yt-dlp template variables: %(title)s, %(channel)s, %(upload_date)s, %(id)s, %(ext)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 164)

                            settingsRow(label: "Auto-organize") {
                                Toggle("", isOn: $settings.autoOrganize)
                                    .labelsHidden()
                                    .onChange(of: settings.autoOrganize) { settings.saveSettings() }
                                if settings.autoOrganize {
                                    Picker("", selection: $settings.organizeBy) {
                                        Text("By Channel").tag("channel")
                                        Text("By Playlist").tag("playlist")
                                        Text("By Date").tag("date")
                                        Text("By Format").tag("format")
                                    }
                                    .labelsHidden()
                                    .frame(width: 120)
                                    .onChange(of: settings.organizeBy) { settings.saveSettings() }
                                }
                            }
                            if settings.autoOrganize {
                                Text("Creates subfolders in the output directory")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 164)
                            }

                            if settings.useDownloadArchive {
                                settingsRow(label: "Archive File") {
                                    Text(DownloadManager.appSupportDirectory().appendingPathComponent("download-archive.txt").path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    }

                    // Output Location
                    settingsSection(title: "Output Location", icon: "folder") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(Color.yellow)
                                Text(settings.outputDirectory.path)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                            }
                            .padding(8)
                            .background(Color(NSColor.textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            )

                            Button("Choose Folder…") {
                                chooseOutputDirectory()
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        }
                    }

                    // yt-dlp Status
                    settingsSection(title: "Backend (yt-dlp)", icon: "terminal") {
                        HStack(spacing: 10) {
                            if manager.isYtdlpInstalled {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("yt-dlp is installed")
                                            .font(.callout)
                                            .fontWeight(.medium)
                                        if !manager.ytdlpCurrentVersion.isEmpty {
                                            Text("v\(manager.ytdlpCurrentVersion)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(manager.ytdlpPath)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)

                                    // Version check & update
                                    HStack(spacing: 8) {
                                        if manager.ytdlpVersionChecking {
                                            ProgressView()
                                                .controlSize(.mini)
                                            Text("Checking for updates…")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else if manager.ytdlpUpdateAvailable {
                                            Image(systemName: "arrow.up.circle.fill")
                                                .foregroundStyle(Color.orange)
                                                .font(.caption)
                                            Text("Update available: \(manager.ytdlpLatestVersion)")
                                                .font(.caption)
                                                .foregroundStyle(.orange)
                                            if manager.ytdlpUpdating {
                                                ProgressView()
                                                    .controlSize(.mini)
                                            } else {
                                                Button("Update") {
                                                    manager.updateYtdlp()
                                                }
                                                .buttonStyle(SecondaryButtonStyle())
                                                .controlSize(.small)
                                            }
                                        } else if !manager.ytdlpCurrentVersion.isEmpty {
                                            Image(systemName: "checkmark.circle")
                                                .foregroundStyle(Color.green)
                                                .font(.caption)
                                            Text("Up to date")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        if !manager.ytdlpVersionChecking && !manager.ytdlpUpdating {
                                            Button("Check for Updates") {
                                                manager.checkYtdlpVersion()
                                            }
                                            .buttonStyle(.plain)
                                            .font(.caption)
                                            .foregroundStyle(Color.accentColor)
                                        }
                                    }
                                    .padding(.top, 4)
                                }
                            } else {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.orange)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("yt-dlp is not installed")
                                        .font(.callout)
                                        .fontWeight(.medium)
                                    Text("Required to download videos")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if manager.isInstallingYtdlp {
                                        HStack(spacing: 6) {
                                            ProgressView()
                                                .controlSize(.mini)
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
                                        .controlSize(.small)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onAppear {
                            if manager.ytdlpCurrentVersion.isEmpty && manager.isYtdlpInstalled {
                                manager.checkYtdlpVersion()
                            }
                        }
                    }

                    // About
                    settingsSection(title: "About", icon: "info.circle") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Star Video Downloader")
                                .fontWeight(.medium)
                            Text("Download videos from YouTube, Vimeo, Twitter/X, TikTok, and 1800+ sites in up to 4K/8K quality.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            Text("Powered by yt-dlp")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
        }
        .frame(width: 520, height: 680)
        .sheet(isPresented: $showUpgradePrompt) {
            UpgradePromptView(reason: upgradeReason)
        }
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(Color.primary)
            content()
        }
    }

    private func settingsRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .frame(width: 160, alignment: .leading)
            content()
        }
    }

    private func activateKey() {
        Task {
            let result = await license.activateLicense(key: licenseKeyInput)
            switch result {
            case .success:
                showLicenseError = false
                licenseKeyInput = ""
            default:
                licenseErrorMessage = license.lastError ?? "Activation failed."
                showLicenseError = true
            }
        }
    }

    private func maskedKey(_ key: String) -> String {
        guard key.count >= 8 else { return key }
        let prefix = key.prefix(8)
        let suffix = String(repeating: "*", count: max(0, key.count - 8))
        return prefix + suffix
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select the folder where videos will be saved."
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputDirectory = url
            settings.saveSettings()
        }
    }
}

#Preview {
    let settings = SettingsManager()
    SettingsView(manager: DownloadManager(settings: settings), settings: settings)
        .environment(LicenseManager())
}
