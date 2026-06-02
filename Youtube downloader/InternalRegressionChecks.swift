import Foundation

enum InternalRegressionChecks {
    private static var hasRun = false

    static func run() {
        #if DEBUG
        guard !hasRun else { return }
        hasRun = true

        let original = DownloadItem(
            url: "https://example.com/watch?v=123",
            quality: .best720,
            format: .mp4,
            subtitles: true,
            playlistDownload: false,
            playlistTitle: "Sample Playlist",
            playlistIndex: 4,
            sourcePlaylistURL: "https://example.com/playlist?list=abc",
            scheduledStartDate: Date(timeIntervalSince1970: 12345)
        )
        original.title = "Sample Title"
        original.channelName = "Sample Channel"
        original.duration = "4:20"
        original.status = .failed("Interrupted by a previous app session. Retry to continue.")
        original.isLiveStream = true
        original.speedHistory = [1_000, 2_000]

        let snapshot = PersistedDownloadItem(item: original)
        let restored = snapshot.makeDownloadItem()

        assert(restored.url == original.url, "Queue persistence should preserve URL.")
        assert(restored.quality == original.quality, "Queue persistence should preserve quality.")
        assert(restored.format == original.format, "Queue persistence should preserve format.")
        assert(restored.playlistTitle == original.playlistTitle, "Queue persistence should preserve playlist title.")
        assert(restored.playlistIndex == original.playlistIndex, "Queue persistence should preserve playlist index.")
        assert(restored.sourcePlaylistURL == original.sourcePlaylistURL, "Queue persistence should preserve playlist source URL.")
        assert(restored.scheduledStartDate == original.scheduledStartDate, "Queue persistence should preserve scheduled dates.")
        assert(restored.isLiveStream == original.isLiveStream, "Queue persistence should preserve live metadata.")

        let waiting = PersistedDownloadStatus(from: .waiting).restoredStatus()
        if case .waiting = waiting {
        } else {
            assertionFailure("Waiting status should survive persistence round-trips.")
        }

        let active = PersistedDownloadStatus(from: .downloading(progress: 0.3, speed: "1 MiB/s", eta: "00:10")).restoredStatus()
        if case .failed(let message) = active {
            assert(message.contains("Interrupted"), "Active downloads should restore with an interruption hint.")
        } else {
            assertionFailure("Active downloads should not silently restore as running.")
        }

        let alreadyMP4 = URL(fileURLWithPath: "/tmp/star-video.mp4")
        let alreadyMP4Destination = DownloadManager.conversionDestination(for: alreadyMP4, preferredExtension: "mp4")
        assert(alreadyMP4Destination.finalOutputURL == alreadyMP4, "Final conversion path should preserve the requested MP4 path.")
        assert(alreadyMP4Destination.ffmpegOutputURL != alreadyMP4, "ffmpeg should not write over its input file.")
        assert(alreadyMP4Destination.ffmpegOutputURL.pathExtension == "mp4", "Temporary conversion output should keep the requested extension.")

        let mergedMKV = URL(fileURLWithPath: "/tmp/star-video.mkv")
        let mergedMKVDestination = DownloadManager.conversionDestination(for: mergedMKV, preferredExtension: "mp4")
        assert(mergedMKVDestination.ffmpegOutputURL == URL(fileURLWithPath: "/tmp/star-video.mp4"), "MKV conversion should target the normal final MP4 path.")
        assert(mergedMKVDestination.finalOutputURL == URL(fileURLWithPath: "/tmp/star-video.mp4"), "Final MKV conversion output should be the MP4 sibling.")

        let existingDownloadLine = "[download] /tmp/Kovan & Inas ｜ Wedding Clip.mp4 has already been downloaded"
        assert(DownloadManager.alreadyDownloadedOutputURL(from: existingDownloadLine)?.path == "/tmp/Kovan & Inas ｜ Wedding Clip.mp4", "Existing yt-dlp outputs should preserve the already downloaded MP4 path.")
        #endif
    }
}
