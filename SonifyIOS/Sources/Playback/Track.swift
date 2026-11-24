import Foundation

/// 播放对象的纯值模型。Android 用 Media3 `MediaItem` + `MediaMetadata`，iOS 不用 AVPlayerItem 当模型
/// （AVPlayerItem 无法 Codable、也不该进 SwiftUI 状态），一律用 Track 传值。
struct Track: Identifiable, Codable, Hashable {

    /// 本地曲：文件绝对路径；在线曲：稳定 hash（对应 Android 的 `kugou://song/<hash>` 占位语义）。
    let id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    /// 本地文件地址；在线曲为 nil（播放时再惰性解析真实 URL）。
    var fileURL: URL?
    var artworkData: Data?
    /// LRC/KRC 原文缓存，随歌曲落盘（对应 Android `LyricDiskCache`）。
    var lyricText: String?

    var isRemote: Bool { fileURL == nil }

    init(
        id: String,
        title: String,
        artist: String = "未知艺人",
        album: String = "未知专辑",
        duration: TimeInterval = 0,
        fileURL: URL? = nil,
        artworkData: Data? = nil,
        lyricText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileURL = fileURL
        self.artworkData = artworkData
        self.lyricText = lyricText
    }
}

extension Track {
    var displaySubtitle: String {
        album.isEmpty || album == "未知专辑" ? artist : "\(artist) · \(album)"
    }

    var durationText: String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
