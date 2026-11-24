import AVFoundation
import Foundation

/// 本地资料库扫描。Android 用 libPhonograph + TagLib；iOS 归一到 AVAsset，
/// 但注意 AVAsset 只读取系统认识的容器（ape/wma/tta 这类要等 M2 接 FFmpeg）。
enum LibraryScanner {

    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "caf", "mp4", "m4b",
        // 下面这些 AVAsset 解不了，先扫进来但播放会失败（M2 接 FFmpeg 后可用）。
        "ogg", "opus", "ape", "wma", "tta",
    ]

    /// 扫描目录（默认沙盒 Documents）。返回的值模型不含任何 AVFoundation 对象，可直接进 SwiftUI 状态。
    static func scan(directory: URL) async -> [Track] {
        var tracks: [Track] = []
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        for case let fileURL as URL in enumerator {
            guard supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true
            else { continue }
            if let track = await makeTrack(url: fileURL) {
                tracks.append(track)
            }
        }

        return tracks.sorted { lhs, rhs in
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    static func makeTrack(url: URL) async -> Track? {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration))?.seconds ?? 0

        var title = url.deletingPathExtension().lastPathComponent
        var artist = "未知艺人"
        var album = "未知专辑"
        var artworkData: Data?

        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let value = try? await item.load(.stringValue), let text = value, !text.isEmpty {
                        title = text
                    }
                case .commonKeyArtist:
                    if let value = try? await item.load(.stringValue), let text = value, !text.isEmpty {
                        artist = text
                    }
                case .commonKeyAlbumName:
                    if let value = try? await item.load(.stringValue), let text = value, !text.isEmpty {
                        album = text
                    }
                case .commonKeyArtwork:
                    if let value = try? await item.load(.dataValue), let data = value {
                        artworkData = data
                    }
                default:
                    break
                }
            }
        }

        // 同目录同名 .lrc 直接吃掉（对应 Android 的本地歌词优先策略）。
        let lyricURL = url.deletingPathExtension().appendingPathExtension("lrc")
        let lyricText = try? String(contentsOf: lyricURL, encoding: .utf8)

        return Track(
            id: url.path,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            fileURL: url,
            artworkData: artworkData,
            lyricText: lyricText
        )
    }
}
