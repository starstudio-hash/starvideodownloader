//
//  HistoryManager.swift
//  Youtube downloader
//

import Foundation

struct HistoryEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var url: String
    var title: String
    var channelName: String
    var date: Date
    var outputPath: String?
    var quality: String
    var format: String
    var fileSize: Int64?

    // Shared formatters — avoid recreating on every row render
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var formattedDate: String {
        Self.dateFormatter.string(from: date)
    }

    var formattedFileSize: String {
        guard let size = fileSize else { return "—" }
        return Self.byteFormatter.string(fromByteCount: size)
    }
}

@Observable
class HistoryManager {
    var entries: [HistoryEntry] = []

    private static var historyFileURL: URL {
        DownloadManager.appSupportDirectory().appendingPathComponent("history.json")
    }

    init() {
        load()
    }

    // MARK: - Record

    func record(item: DownloadItem) {
        var fileSize: Int64? = nil
        if let path = item.outputPath {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
               let size = attrs[.size] as? Int64 {
                fileSize = size
            }
        }

        let entry = HistoryEntry(
            url: item.url,
            title: item.title,
            channelName: item.channelName,
            date: Date(),
            outputPath: item.outputPath?.path,
            quality: item.quality.rawValue,
            format: item.format.rawValue,
            fileSize: fileSize
        )
        entries.insert(entry, at: 0)
        save()
    }

    // MARK: - Search

    func search(query: String) -> [HistoryEntry] {
        guard !query.isEmpty else { return entries }
        let lower = query.lowercased()
        return entries.filter {
            $0.title.lowercased().contains(lower) ||
            $0.url.lowercased().contains(lower) ||
            $0.channelName.lowercased().contains(lower)
        }
    }

    // MARK: - Delete

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }

    // MARK: - Export

    func exportJSON() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(entries)
    }

    func exportCSV() -> String {
        var csv = "Title,URL,Channel,Date,Quality,Format,File Size\n"
        for entry in entries {
            let fields = [
                entry.title,
                entry.url,
                entry.channelName,
                entry.formattedDate,
                entry.quality,
                entry.format,
                entry.formattedFileSize
            ].map { csvQuote($0) }
            csv += fields.joined(separator: ",") + "\n"
        }
        return csv
    }

    /// Properly quotes a CSV field per RFC 4180
    private func csvQuote(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    // MARK: - Persistence

    /// Serialization queue to avoid concurrent file writes and keep main thread free.
    private static let saveQueue = DispatchQueue(label: "com.youtubedownloader.history-save", qos: .utility)

    private func save() {
        let snapshot = entries
        let url = Self.historyFileURL
        Self.saveQueue.async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: url)
            }
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: Self.historyFileURL.path) else { return }
        guard let data = try? Data(contentsOf: Self.historyFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }
}
