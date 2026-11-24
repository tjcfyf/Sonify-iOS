import SwiftUI
import UniformTypeIdentifiers

/// 资料库页。Android 对应 `ui/pages/library`：字母索引 + 多场景排序，M0 先做搜索/分组/导入。
struct LibraryView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var isImporting = false
    @State private var sortMode: SortMode = .title

    private enum SortMode: String, CaseIterable, Hashable {
        case title = "按标题"
        case artist = "按艺人"
        case duration = "按时长"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, Theme.pagePadding)
                    .padding(.bottom, 12)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(groups, id: \.key) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.key)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Theme.tertiaryText)
                                    .padding(.horizontal, 4)
                                VStack(spacing: 0) {
                                    ForEach(group.tracks) { track in
                                        TrackRow(
                                            track: track,
                                            isCurrent: engine.currentTrack?.id == track.id,
                                            showsFavorite: true,
                                            isFavorite: library.isFavorite(track),
                                            onTap: {
                                                let queue = library.filteredTracks
                                                engine.play(queue: queue, startAt: queue.firstIndex(of: track) ?? 0)
                                            },
                                            onToggleFavorite: { library.toggleFavorite(track) }
                                        )
                                    }
                                }
                            }
                        }
                        if library.filteredTracks.isEmpty {
                            Text(library.tracks.isEmpty ? "还没有歌曲，点右上角导入。" : "没有匹配的结果。")
                                .font(.system(size: 14))
                                .foregroundColor(Theme.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 60)
                        }
                    }
                    .pagePadding()
                    .padding(.bottom, 130)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("资料库")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isImporting = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(settings.accent)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("排序", selection: $sortMode) {
                            ForEach(SortMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        Button("重新扫描") {
                            Task { await library.refresh() }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.primaryText)
                    }
                }
            }
        }
        .navigationViewStyle(.stack)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav, .aiff],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                library.importFiles(urls)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.tertiaryText)
            TextField("搜索歌曲、艺人、专辑", text: $library.searchText)
                .font(.system(size: 14))
                .foregroundColor(Theme.primaryText)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
            if !library.searchText.isEmpty {
                Button {
                    library.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Theme.tertiaryText)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(GlassSurface(style: GlassStyle(intensity: 0.75, cornerRadius: 16)) { Color.clear })
    }

    private var groups: [(key: String, tracks: [Track])] {
        let source: [Track]
        switch sortMode {
        case .title:
            source = library.filteredTracks
        case .artist:
            source = library.filteredTracks.sorted {
                $0.artist.localizedStandardCompare($1.artist) == .orderedAscending
            }
        case .duration:
            source = library.filteredTracks.sorted { $0.duration < $1.duration }
        }

        let grouped = Dictionary(grouping: source) { track -> String in
            guard let first = track.title.first else { return "#" }
            return first.isLetter ? String(first).uppercased() : "#"
        }
        return grouped
            .map { (key: $0.key, tracks: $0.value) }
            .sorted { lhs, rhs in
                if lhs.key == "#" { return false }
                if rhs.key == "#" { return true }
                return lhs.key < rhs.key
            }
    }
}
