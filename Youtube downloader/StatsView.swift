//
//  StatsView.swift
//  Youtube downloader
//

import SwiftUI

enum StatsTimeFilter: String, CaseIterable, Identifiable {
    case all = "All Time"
    case last30Days = "Last 30 Days"
    case last7Days = "Last 7 Days"

    var id: String { rawValue }
}

/// Pre-computed stats snapshot — built once per history change, not per SwiftUI body evaluation.
struct StatsSnapshot {
    let totalDownloads: Int
    let totalSize: Int64
    let formattedTotalSize: String
    let downloadsByFormat: [(String, Int)]
    let downloadsByQuality: [(String, Int)]
    let topChannels: [(String, Int)]
    let downloadsByDay: [(String, Int)]
    let averageSize: String

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// Sortable key so days sort chronologically, not alphabetically.
    private static let sortKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(entries: [HistoryEntry]) {
        totalDownloads = entries.count
        totalSize = entries.compactMap { $0.fileSize }.reduce(0, +)
        formattedTotalSize = Self.byteFormatter.string(fromByteCount: totalSize)
        let averageBytes = entries.isEmpty ? 0 : totalSize / Int64(max(entries.count, 1))
        averageSize = Self.byteFormatter.string(fromByteCount: averageBytes)

        var fmtCounts: [String: Int] = [:]
        var qualCounts: [String: Int] = [:]
        var chanCounts: [String: Int] = [:]
        var dayCounts: [String: (display: String, count: Int)] = [:]

        for entry in entries {
            fmtCounts[entry.format, default: 0] += 1
            qualCounts[entry.quality, default: 0] += 1
            if !entry.channelName.isEmpty {
                chanCounts[entry.channelName, default: 0] += 1
            }
            let sortKey = Self.sortKeyFormatter.string(from: entry.date)
            let displayKey = Self.dayFormatter.string(from: entry.date)
            dayCounts[sortKey, default: (display: displayKey, count: 0)].count += 1
        }

        downloadsByFormat = fmtCounts.sorted { $0.value > $1.value }
        downloadsByQuality = qualCounts.sorted { $0.value > $1.value }
        topChannels = chanCounts.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value) }
        downloadsByDay = dayCounts.sorted { $0.key < $1.key }.suffix(14).map { ($0.value.display, $0.value.count) }
    }
}

struct StatsView: View {
    var manager: DownloadManager
    @State private var timeFilter: StatsTimeFilter = .all

    private var stats: StatsSnapshot {
        let filteredEntries = manager.historyManager.entries.filter { entry in
            switch timeFilter {
            case .all:
                return true
            case .last30Days:
                return entry.date >= Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
            case .last7Days:
                return entry.date >= Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
            }
        }
        return StatsSnapshot(entries: filteredEntries)
    }

    var body: some View {
        let s = stats
        ScrollView {
            if s.totalDownloads == 0 {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                    Text("No statistics yet")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    Text("Download some videos to see statistics here.")
                        .font(.callout)
                        .foregroundStyle(Color.secondary.opacity(0.7))
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Range", selection: $timeFilter) {
                        ForEach(StatsTimeFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)

                    // Live Bandwidth
                    if manager.bandwidthHistory.contains(where: { $0 > 0 }) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Live Bandwidth")
                                .font(.headline)
                            BandwidthChartView(data: manager.bandwidthHistory)
                                .frame(height: 80)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    // Summary cards
                    HStack(spacing: 16) {
                        statCard(title: "Total Downloads", value: "\(s.totalDownloads)", icon: "arrow.down.circle.fill", color: .blue)
                        statCard(title: "Total Size", value: s.formattedTotalSize, icon: "internaldrive.fill", color: .orange)
                        statCard(title: "Formats Used", value: "\(s.downloadsByFormat.count)", icon: "film", color: .purple)
                        statCard(title: "Channels", value: "\(s.topChannels.count)", icon: "person.2.fill", color: .green)
                    }

                    if !insights(for: s).isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Insights")
                                .font(.headline)
                            ForEach(insights(for: s), id: \.self) { insight in
                                Label(insight, systemImage: "lightbulb")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 24) {
                        // Downloads by Format
                        VStack(alignment: .leading, spacing: 8) {
                            Text("By Format")
                                .font(.headline)
                            ForEach(s.downloadsByFormat, id: \.0) { format, count in
                                barRow(label: format, count: count, max: s.downloadsByFormat.first?.1 ?? 1, color: .blue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Downloads by Quality
                        VStack(alignment: .leading, spacing: 8) {
                            Text("By Quality")
                                .font(.headline)
                            ForEach(s.downloadsByQuality, id: \.0) { quality, count in
                                barRow(label: quality, count: count, max: s.downloadsByQuality.first?.1 ?? 1, color: .orange)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Top channels
                    if !s.topChannels.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Top Channels")
                                .font(.headline)
                            ForEach(s.topChannels, id: \.0) { channel, count in
                                barRow(label: channel, count: count, max: s.topChannels.first?.1 ?? 1, color: .green)
                            }
                        }
                    }

                    // Recent activity
                    if !s.downloadsByDay.isEmpty {
                        let maxCount = s.downloadsByDay.map(\.1).max() ?? 1
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Activity")
                                .font(.headline)
                            HStack(alignment: .bottom, spacing: 4) {
                                ForEach(s.downloadsByDay, id: \.0) { day, count in
                                    VStack(spacing: 2) {
                                        Text("\(count)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.accentColor)
                                            .frame(width: 28, height: max(CGFloat(count) / CGFloat(maxCount) * 80, 4))
                                        Text(day)
                                            .font(.system(size: 8))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    // MARK: - Components

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private func barRow(label: String, count: Int, max: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.callout)
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.7))
                    .frame(width: max > 0 ? geo.size.width * CGFloat(count) / CGFloat(max) : 0)
            }
            .frame(height: 14)
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func insights(for stats: StatsSnapshot) -> [String] {
        var results: [String] = []
        if let topFormat = stats.downloadsByFormat.first {
            results.append("Most common format: \(topFormat.0) (\(topFormat.1) downloads)")
        }
        if let topQuality = stats.downloadsByQuality.first {
            results.append("Most used quality: \(topQuality.0)")
        }
        if let topChannel = stats.topChannels.first {
            results.append("Top source: \(topChannel.0)")
        }
        if stats.totalDownloads > 0 {
            results.append("Average file size: \(stats.averageSize)")
        }
        return results
    }
}

// MARK: - Bandwidth Chart

struct BandwidthChartView: View {
    let data: [Double]

    private static let speedFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()

    var body: some View {
        let maxVal = data.max() ?? 1
        Canvas { context, size in
            guard data.count >= 2, maxVal > 0 else { return }
            let stepX = size.width / CGFloat(data.count - 1)
            let padding: CGFloat = 4

            // Fill area
            var fillPath = Path()
            fillPath.move(to: CGPoint(x: 0, y: size.height))
            for (i, val) in data.enumerated() {
                let x = CGFloat(i) * stepX
                let y = padding + (size.height - 2 * padding) * (1 - CGFloat(val / maxVal))
                fillPath.addLine(to: CGPoint(x: x, y: y))
            }
            fillPath.addLine(to: CGPoint(x: CGFloat(data.count - 1) * stepX, y: size.height))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(.blue.opacity(0.15)))

            // Line
            var linePath = Path()
            for (i, val) in data.enumerated() {
                let x = CGFloat(i) * stepX
                let y = padding + (size.height - 2 * padding) * (1 - CGFloat(val / maxVal))
                if i == 0 { linePath.move(to: CGPoint(x: x, y: y)) }
                else { linePath.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(linePath, with: .color(.blue), lineWidth: 1.5)
        }
        .overlay(alignment: .topTrailing) {
            if let last = data.last, last > 0 {
                Text(Self.speedFormatter.string(fromByteCount: Int64(last)) + "/s")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
        }
    }
}
