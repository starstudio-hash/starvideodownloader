//
//  Youtube_downloaderApp.swift
//  Youtube downloader
//

import SwiftUI
import UserNotifications

extension Notification.Name {
    static let pasteAndDownload = Notification.Name("pasteAndDownload")
    static let showBatchInput = Notification.Name("showBatchInput")
    static let clearCompleted = Notification.Name("clearCompleted")
    static let showSettings = Notification.Name("showSettings")
    static let switchTab = Notification.Name("switchTab")
}

@main
struct Youtube_downloaderApp: App {
    @State private var settings = SettingsManager()
    @State private var manager: DownloadManager
    @State private var licenseManager = LicenseManager()

    init() {
        let s = SettingsManager()
        let lm = LicenseManager()
        _settings = State(initialValue: s)
        _licenseManager = State(initialValue: lm)
        _manager = State(initialValue: DownloadManager(settings: s, licenseManager: lm))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .navigationTitle("Star Video Downloader")
                .environment(manager)
                .environment(licenseManager)
                .onAppear {
                    // Request notification permission on first launch
                    if settings.notificationsEnabled {
                        requestNotificationPermission()
                    }
                    // Start clipboard monitoring if enabled
                    if settings.clipboardMonitoring {
                        manager.startClipboardMonitoring()
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 860, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("Downloads") {
                Button("Paste & Download") {
                    NotificationCenter.default.post(name: .pasteAndDownload, object: nil)
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button("Batch URL Input") {
                    NotificationCenter.default.post(name: .showBatchInput, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Divider()

                Button("Clear Completed") {
                    NotificationCenter.default.post(name: .clearCompleted, object: nil)
                }
                .keyboardShortcut("k", modifiers: .command)
            }

            CommandGroup(after: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("Tabs") {
                Button("Downloads") {
                    NotificationCenter.default.post(name: .switchTab, object: AppTab.downloads)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Convert") {
                    NotificationCenter.default.post(name: .switchTab, object: AppTab.convert)
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("History") {
                    NotificationCenter.default.post(name: .switchTab, object: AppTab.history)
                }
                .keyboardShortcut("3", modifiers: .command)

                Button("Stats") {
                    NotificationCenter.default.post(name: .switchTab, object: AppTab.stats)
                }
                .keyboardShortcut("4", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarView(manager: manager)
        } label: {
            Label {
                Text("Star Video Downloader")
            } icon: {
                Image(systemName: "arrow.down.circle.fill")
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

// MARK: - Menu Bar View

struct MenuBarView: View {
    var manager: DownloadManager

    var body: some View {
        let activeItems = manager.items.filter { $0.status.isActive }
        let completedCount = manager.items.filter {
            if case .completed = $0.status { return true }
            return false
        }.count

        if activeItems.isEmpty {
            Text("No active downloads")
                .foregroundStyle(.secondary)
        } else {
            Text("\(activeItems.count) active download\(activeItems.count == 1 ? "" : "s")")
                .fontWeight(.medium)

            Divider()

            ForEach(activeItems.prefix(5)) { item in
                VStack(alignment: .leading) {
                    Text(item.title == item.url ? "Downloading…" : item.title)
                        .lineLimit(1)
                    Text(item.status.displayText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if activeItems.count > 5 {
                Text("+ \(activeItems.count - 5) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if completedCount > 0 {
            Divider()
            Text("\(completedCount) completed")
                .foregroundStyle(.secondary)
        }

        Divider()

        Button("Open Star Video Downloader") {
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
        .keyboardShortcut("o")

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
