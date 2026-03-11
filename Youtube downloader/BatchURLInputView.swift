//
//  BatchURLInputView.swift
//  Youtube downloader
//

import SwiftUI

struct BatchURLInputView: View {
    @Bindable var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @Environment(LicenseManager.self) private var license

    @State private var urlText: String = ""
    @State private var selectedQuality: VideoQuality = .best1080
    @State private var selectedFormat: OutputFormat = .mp4
    @State private var downloadSubtitles: Bool = false
    @State private var showUpgradePrompt: Bool = false

    private var parsedURLs: [String] {
        urlText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && isValidURL($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Batch URL Input")
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

            VStack(alignment: .leading, spacing: 12) {
                Text("Paste one URL per line:")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextEditor(text: $urlText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )

                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Text("Quality:")
                            .font(.callout)
                        Picker("", selection: $selectedQuality) {
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
                                showUpgradePrompt = true
                            }
                        }
                    }

                    HStack(spacing: 6) {
                        Text("Format:")
                            .font(.callout)
                        Picker("", selection: $selectedFormat) {
                            ForEach(OutputFormat.allCases) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }

                    Toggle("Subtitles", isOn: $downloadSubtitles)
                        .toggleStyle(.checkbox)
                }

                HStack {
                    let count = parsedURLs.count
                    Text("\(count) valid URL\(count == 1 ? "" : "s") found")
                        .font(.caption)
                        .foregroundStyle(count > 0 ? .primary : .secondary)

                    Spacer()

                    Button("Paste from Clipboard") {
                        if let str = NSPasteboard.general.string(forType: .string) {
                            if urlText.isEmpty {
                                urlText = str
                            } else {
                                urlText += "\n" + str
                            }
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(16)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.escape)

                Button("Add \(parsedURLs.count) Download\(parsedURLs.count == 1 ? "" : "s")") {
                    guard license.hasFullAccess else { return }
                    for url in parsedURLs {
                        guard license.canDownload else { break }
                        if manager.settings.duplicateHandling == .allow || manager.duplicateMessage(for: url) == nil {
                            manager.addDownload(
                                url: url,
                                quality: selectedQuality,
                                format: selectedFormat,
                                subtitles: downloadSubtitles
                            )
                        }
                    }
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(parsedURLs.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(12)
        }
        .frame(width: 540, height: 420)
        .sheet(isPresented: $showUpgradePrompt) {
            UpgradePromptView(reason: .qualityRestricted)
        }
    }

    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host, host.contains(".")
        else { return false }
        return true
    }
}
