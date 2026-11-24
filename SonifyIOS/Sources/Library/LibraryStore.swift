import Combine
import Foundation

/// 资料库状态。对应 Android `data/libraries` + `FavoriteRepository`。
@MainActor
final class LibraryStore: ObservableObject {

    static let shared = LibraryStore()

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?
    @Published var searchText: String = ""

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

    private init() {
        Task { await refresh() }
    }

    func refresh() async {
        isScanning = true
        let scanned = await LibraryScanner.scan(directory: documentsURL)
        // 保留上次扫进内存的封面/歌词（重扫时不必再解一遍），文件不存在的旧条目直接丢。
        tracks = scanned
        isScanning = false
        lastScanDate = Date()
        objectWillChange.send()
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
