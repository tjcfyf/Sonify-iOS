import Combine
import Foundation

/// 删除落盘逻辑单独抽出来，方便单元测试（Services 里不依赖 SwiftUI）。
enum TrackFileRemoval {
    @discardableResult
    static func remove(audio url: URL, fileManager: FileManager = .default) -> Bool {
        var removedAny = false
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
                removedAny = true
            } catch {
                // 删不掉文件也别阻断：调用方随后会把它从库里摘掉。
            }
        }
        let lyricURL = url.deletingPathExtension().appendingPathExtension("lrc")
        if fileManager.fileExists(atPath: lyricURL.path) {
            try? fileManager.removeItem(at: lyricURL)
        }
        // 若所在子目录已空（演示曲的「示例曲」目录），一起收掉，避免留空壳目录。
        let folder = url.deletingLastPathComponent()
        if let contents = try? fileManager.contentsOfDirectory(atPath: folder.path), contents.isEmpty {
            try? fileManager.removeItem(at: folder)
        }
        return removedAny
    }
}

/// 资料库状态。对应 Android `data/libraries` + `FavoriteRepository`。
@MainActor
final class LibraryStore: ObservableObject {

    static let shared = LibraryStore()

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?
    @Published var searchText: String = ""
    @Published private(set) var isGeneratingDemo = false
    @Published private(set) var lastError: String?

    private let favoritesKey = "sonify.favorites"

    var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// MochiIndexBar 的 iOS 等价：按首字母/首字分组。
    var groupedByInitial: [(key: String, tracks: [Track])] {
        let source = filteredTracks
        let groups = Dictionary(grouping: source) { track -> String in
            guard let first = track.title.first else { return "#" }
            if first.isLetter { return String(first).uppercased() }
            return "#"
        }
        return groups
            .map { (key: $0.key, tracks: $0.value.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) }
            .sorted { lhs, rhs in
                if lhs.key == "#" { return false }
                if rhs.key == "#" { return true }
                return lhs.key < rhs.key
            }
    }

    var filteredTracks: [Track] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.localizedCaseInsensitiveContains(keyword)
                || $0.artist.localizedCaseInsensitiveContains(keyword)
                || $0.album.localizedCaseInsensitiveContains(keyword)
        }
    }

    private init() {}

    /// 首帧之后再扫，避免启动时同步枚举大目录。
    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            await refresh()
        }
    }

    private var didBootstrap = false

    func refresh() async {
        isScanning = true
        let scanned = await LibraryScanner.scan(directory: documentsURL)
        // 保留上次扫进内存的封面/歌词（重扫时不必再解一遍），文件不存在的旧条目直接丢。
        tracks = scanned
        isScanning = false
        lastScanDate = Date()
        objectWillChange.send()
    }

    /// 生成一首本地合成演示曲（无版权、无网络），用于"暂时没有歌"时验证播放与歌词。
    /// 放到后台线程写文件，避免主线程卡顿；失败会把原因留在 `lastError`。
    func createDemoTrack() {
        guard !isGeneratingDemo else { return }
        isGeneratingDemo = true
        lastError = nil
        let directory = documentsURL

        Task {
            let created = await Task.detached(priority: .userInitiated) { () -> Bool in
                DemoTrackFactory.ensure(in: directory) != nil
            }.value

            isGeneratingDemo = false
            if created {
                await refresh()
                if tracks.isEmpty {
                    lastError = "演示曲已生成，但扫描没找到，试试设置里「重新扫描」"
                }
            } else {
                lastError = "演示曲生成失败（写文件出错）"
            }
        }
    }

    func importFiles(_ urls: [URL]) {
        let fileManager = FileManager.default
        for url in urls {
            let needsSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if needsSecurityScope { url.stopAccessingSecurityScopedResource() }
            }
            var destination = documentsURL.appendingPathComponent(url.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                destination = documentsURL.appendingPathComponent(
                    "\(url.deletingPathExtension().lastPathComponent)-\(UUID().uuidString.prefix(6)).\(url.pathExtension)"
                )
            }
            try? fileManager.copyItem(at: url, to: destination)
        }
        Task { await refresh() }
    }

    /// 删除一首歌：文件、同名歌词、收藏记录、播放队列一起清。
    /// 即使文件删失败（占位、权限）也必须把条目从内存里摘掉，否则用户会觉得"删不掉"。
    func delete(_ track: Track) {
        if let url = track.fileURL {
            TrackFileRemoval.remove(audio: url)
        }

        tracks.removeAll { $0.id == track.id || $0.fileURL == track.fileURL }

        var ids = favoriteIDs
        ids.remove(track.id)
        favoriteIDs = ids

        // 队列里的同一首（按 id 和文件地址双匹配）一起下掉。
        PlayerEngine.shared.handleTrackDeleted(track.id, fileURL: track.fileURL)
    }

    func isFavorite(_ track: Track) -> Bool {
        favoriteIDs.contains(track.id)
    }

    func toggleFavorite(_ track: Track) {
        var ids = favoriteIDs
        if ids.contains(track.id) {
            ids.remove(track.id)
        } else {
            ids.insert(track.id)
        }
        favoriteIDs = ids
    }

    var favoriteTracks: [Track] {
        tracks.filter { favoriteIDs.contains($0.id) }
    }

    private var favoriteIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: favoritesKey) }
    }
}
