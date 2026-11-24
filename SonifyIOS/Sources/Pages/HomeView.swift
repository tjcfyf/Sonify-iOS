import SwiftUI

/// 首页。Android `Home.kt` 是信息流式排版（今日推荐/歌单/画廊），M0 只做「最近 + 收藏 + 本地入口」。
struct HomeView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var router: TabRouter

    private var recentTracks: [Track] {
        Array(library.tracks.suffix(12)).reversed()
    }

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    quickRow
                    if library.tracks.isEmpty {
                        emptyState
                    } else {
                        section(title: "最近添加", subtitle: "本地 \(library.tracks.count) 首") {
                            recentGrid
                        }
                        if !library.favoriteTracks.isEmpty {
                            section(title: "我的收藏", subtitle: "\(library.favoriteTracks.count) 首") {
                                favoriteList
                            }
                        }
                    }
                    onlinePlaceholder
                }
                .pagePadding()
                .padding(.top, 8)
                .padding(.bottom, 120)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 组件

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sonify")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(Theme.primaryText)
                Text("本地曲库 · \(library.isScanning ? "正在扫描…" : "\(library.tracks.count) 首")")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
            }
            Spacer()
            HStack(spacing: 10) {
                GlassCircleButton(systemName: "magnifyingglass") {
                    router.openLibrarySearch()
                }
                GlassCircleButton(systemName: "gearshape.fill") {
                    router.openSettings()
                }
            }
        }
    }

    private var quickRow: some View {
        HStack(spacing: 12) {
            quickCard(title: "全部歌曲", icon: "music.note.list", value: "\(library.tracks.count)") {
                router.openLibrary()
            }
            quickCard(title: "收藏", icon: "heart.fill", value: "\(library.favoriteTracks.count)") {
                router.openLibrary()
            }
            quickCard(title: "设置", icon: "slider.horizontal.3", value: "\(Theme.accents.count) 色") {
                router.openSettings()
            }
        }
    }

    private func quickCard(
        title: String,
        icon: String,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            GlassSurface(style: settings.glassStyle) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(settings.accent)
                    Text(value)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.primaryText)
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
        .buttonStyle(GlassPressStyle())
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(Theme.primaryText)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.tertiaryText)
                Spacer()
            }
            content()
        }
    }

    private var recentGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(recentTracks) { track in
                    Button {
                        engine.play(queue: recentTracks, startAt: recentTracks.firstIndex(of: track) ?? 0)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            ArtworkView(track: track, cornerRadius: 20)
                                .frame(width: 140, height: 140)
                            Text(track.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Theme.primaryText)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Theme.secondaryText)
                                .lineLimit(1)
                        }
                        .frame(width: 140, alignment: .leading)
                    }
                    .buttonStyle(GlassPressStyle())
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var favoriteList: some View {
        VStack(spacing: 2) {
            ForEach(library.favoriteTracks.prefix(5)) { track in
                TrackRow(track: track, isCurrent: engine.currentTrack?.id == track.id) {
                    engine.play(queue: library.favoriteTracks, startAt: library.favoriteTracks.firstIndex(of: track) ?? 0)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            GlassSurface(style: settings.glassStyle) { Color.clear }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ArtworkView(track: nil, cornerRadius: 24)
                .frame(width: 120, height: 120)
            if library.isGeneratingDemo {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.secondaryText))
            }
            Text("还没有本地音乐")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Theme.primaryText)
            Text("用「资料库」右上角的 + 导入音频文件，或把文件拷进 Sonify 的 Documents。\n没有歌也能先点下面生成一段演示音频来试播放与歌词。")
                .font(.system(size: 13))
                .foregroundColor(Theme.secondaryText)
                .multilineTextAlignment(.center)
            if let error = library.lastError {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.accents[0])
                    .multilineTextAlignment(.center)
            }
            Button {
                library.createDemoTrack()
            } label: {
                Text("生成演示曲")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(settings.accent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        GlassSurface(style: GlassStyle(intensity: 0.8, cornerRadius: 14)) { Color.clear }
                    )
            }
            .buttonStyle(GlassPressStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var onlinePlaceholder: some View {
        GlassSurface(style: GlassStyle(intensity: 0.7, cornerRadius: Theme.cardRadius)) {
            VStack(alignment: .leading, spacing: 6) {
                Text("在线曲库 · 待接入")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.primaryText)
                Text("酷狗能力依赖 Android 侧的 libkugou_server.so（Rust 本地 HTTP 服务）。iOS 需先交叉编译该服务或走中转方案，详见移植方案 §3.4。")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
    }
}

/// 通用列表行（首页收藏、资料库、队列共用）。
struct TrackRow: View {
    let track: Track
    var isCurrent: Bool = false
    var showsFavorite: Bool = false
    var isFavorite: Bool = false
    var onTap: () -> Void
    var onToggleFavorite: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ArtworkView(track: track, cornerRadius: 10)
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isCurrent ? Theme.accents[7] : Theme.primaryText)
                        .lineLimit(1)
                    Text(track.displaySubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                if showsFavorite, let onToggleFavorite = onToggleFavorite {
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isFavorite ? Theme.accents[0] : Theme.tertiaryText)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                }
                if let onDelete = onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.accents[0])
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                }
                Text(track.durationText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(Theme.tertiaryText)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
