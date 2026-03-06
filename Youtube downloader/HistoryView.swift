//
//  HistoryView.swift
//  Youtube downloader
//

import SwiftUI
import UniformTypeIdentifiers

struct HistoryView: View {
    var manager: DownloadManager
    var historyManager: HistoryManager { manager.historyManager }
    @State private var searchQuery: String = ""
    @State private var showClearConfirm: Bool = false

    private var filteredEntries: [HistoryEntry] {
        historyManager.search(query: searchQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Search history…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .frame(width: 200)

                Spacer()

                Text("\(filteredEntries.count) of \(historyManager.entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Export JSON") {
                    exportJSON()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)

                Button("Export CSV") {
                    exportCSV()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)

                Text("·")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Clear All") {
                    showClearConfirm = true
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if filteredEntries.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "clock.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    Text(historyManager.entries.isEmpty ? "No download history" : "No results")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text(historyManager.entries.isEmpty ?
                         "Completed downloads will be recorded here automatically." :
                         "Try a different search query.")
                        .font(.callout)
                        .foregroundStyle(Color.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredEntries) { entry in
                            HistoryRowView(entry: entry, historyManager: historyManager, downloadManager: manager)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
            }
        }
        .alert("Clear History?", isPresented: $showClearConfirm) {
            Button("Clear All", role: .destructive) {
                historyManager.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all download history. This cannot be undone.")
        }
    }

    private func exportJSON() {
        guard let data = historyManager.exportJSON() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "download-history.json"
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    private func exportCSV() {
        let csv = historyManager.exportCSV()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "download-history.csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - History Row View

struct HistoryRowView: View {
    var entry: HistoryEntry
    var historyManager: HistoryManager
    var downloadManager: DownloadManager
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.green.opacity(0.6))
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if !entry.channelName.isEmpty {
                        Label(entry.channelName, systemImage: "person.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Label(entry.quality, systemImage: "4k.tv")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Label(entry.format, systemImage: "film")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.formattedFileSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(entry.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if isHovered {
                HStack(spacing: 8) {
                    if let path = entry.outputPath {
                        let url = URL(fileURLWithPath: path)
                        if FileManager.default.fileExists(atPath: path) {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: {
                                Image(systemName: "folder")
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                            .help("Show in Finder")
                        }
                    }

                    Button {
                        downloadManager.addDownload(url: entry.url)
                    } label: {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .help("Re-download")

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.url, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy URL")

                    Button {
                        historyManager.delete(entry)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from history")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title), \(entry.quality), \(entry.format), \(entry.formattedDate)")
    }
}
