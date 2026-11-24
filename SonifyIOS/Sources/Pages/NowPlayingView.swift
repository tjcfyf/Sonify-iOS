import SwiftUI

/// 播放页。Android `NowPlaying.kt` + `NowPlayingLandscape.kt` 是玻璃 + Pear Wall 背景 + 逐字歌词，
/// M0 先落「封面/歌词切换 + 进度 + 控制 + 队列」。
struct NowPlayingView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var showsLyrics = false
    @State private var showsQueue = false
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0

    private var track: Track? { engine.currentTrack }

    private var lyrics: [LyricEntry] {
        guard let text = track?.lyricText, !text.isEmpty else { return [] }
        return LyricParser.parse(text: text, totalDuration: track?.duration ?? 0)
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                if showsLyrics {
                    lyricsPanel
                        .frame(maxHeight: .infinity)
                } else {
                    artworkPanel
                }
                Spacer(minLength: 8)
                trackInfo
                progressSection
                    .padding(.top, 18)
                controls
                    .padding(.top, 22)
                    .padding(.bottom, 12)
                bottomTools
                    .padding(.bottom, 28)
            }
            .pagePadding()
        }
        .sheet(isPresented: $showsQueue) {
            queueSheet
        }
        .onAppear {
            scrubTime = engine.currentTime
        }
    }

    // MARK: - 背景

    private var background: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            // 封面取色的简化版：用封面色块做超大模糊，M2 换成 Palette 真实取色 + Pear Wall。
            ArtworkView(track: track, cornerRadius: 0)
                .scaleEffect(1.6)
                .blur(radius: 90, opaque: true)
                .opacity(0.55)
                .ignoresSafeArea()
            LinearGradient(
                colors: [Color.black.opacity(0.15), Color.black.opacity(0.65)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack {
            GlassCircleButton(systemName: "chevron.down", size: 38) { dismiss() }
            Spacer()
            VStack(spacing: 2) {
                Text("正在播放")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.tertiaryText)
                Text(track?.album ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            GlassCircleButton(systemName: "list.bullet", size: 38) { showsQueue = true }
        }
        .padding(.top, 8)
    }

    // MARK: - 封面 / 歌词

    private var artworkPanel: some View {
        ArtworkView(track: track, cornerRadius: 28)
            .frame(maxWidth: 300, maxHeight: 300)
            .shadow(color: Color.black.opacity(0.5), radius: 30, x: 0, y: 18)
            .padding(.top, 12)
    }

    private var lyricsPanel: some View {
        Group {
            if lyrics.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 26))
                        .foregroundColor(Theme.tertiaryText)
                    Text("暂无歌词")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                    Text("把同名 .lrc 放到歌曲同目录，或等 M4 接入在线歌词。")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.tertiaryText)
                }
            } else {
                LyricsView(
                    entries: lyrics,
                    timeMs: Float(engine.currentTime * 1000),
                    accent: settings.accent,
                    showTranslation: settings.showTranslation
                )
            }
        }
    }

    // MARK: - 曲目信息

    private var trackInfo: some View {
        VStack(spacing: 6) {
            Text(track?.title ?? "未在播放")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(track?.artist ?? "—")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)
        }
        .padding(.top, 10)
    }

    // MARK: - 进度

    private var progressSection: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubTime : engine.currentTime },
                    set: { value in
                        scrubTime = value
                        engine.scrub(to: value)
                    }
                ),
                in: 0...max(0.1, engine.duration),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if editing {
                        scrubTime = engine.currentTime
                        engine.beginScrubbing()
                    } else {
                        engine.endScrubbing()
                    }
                }
            )
            .tint(settings.accent)

            HStack {
                Text(timeText(isScrubbing ? scrubTime : engine.currentTime))
                Spacer()
                Text("-" + timeText(max(0, engine.duration - (isScrubbing ? scrubTime : engine.currentTime))))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundColor(Theme.tertiaryText)
        }
    }

    private func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - 控制

    private var controls: some View {
        HStack(spacing: 26) {
            Button {
                engine.setRate(1.0)
            } label: {
                Text(String(format: "%.1fx", Double(engine.playbackRate)))
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundColor(Theme.secondaryText)
                    .frame(width: 38, height: 30)
            }
            .buttonStyle(.plain)

            Button(action: engine.previous) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.primaryText)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(GlassPressStyle())

            Button(action: engine.togglePlayPause) {
                GlassSurface(style: GlassStyle(intensity: 1.0, cornerRadius: 38)) {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(Theme.primaryText)
                        .frame(width: 76, height: 76)
                }
            }
            .buttonStyle(GlassPressStyle())

            Button(action: engine.next) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Theme.primaryText)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(GlassPressStyle())

            Menu {
                ForEach([0.5, 1.0, 1.25, 1.5, 2.0, 3.0], id: \.self) { rate in
                    Button(String(format: "%.2fx", rate)) {
                        engine.setRate(Float(rate))
                    }
                }
            } label: {
                Image(systemName: "speedometer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.secondaryText)
                    .frame(width: 38, height: 30)
            }
        }
    }

    // MARK: - 底部工具

    private var bottomTools: some View {
        HStack(spacing: 10) {
            Button {
                showsLyrics.toggle()
            } label: {
                toolChip(
                    icon: showsLyrics ? "music.note" : "text.alignleft",
                    title: showsLyrics ? "封面" : "歌词",
                    highlighted: showsLyrics
                )
            }
            .buttonStyle(.plain)

            Menu {
                Button("15 分钟") { engine.startSleepTimer(minutes: 15) }
                Button("30 分钟") { engine.startSleepTimer(minutes: 30) }
                Button("60 分钟") { engine.startSleepTimer(minutes: 60) }
                if engine.sleepRemaining != nil {
                    Button("关闭定时", role: .destructive) { engine.cancelSleepTimer() }
                }
            } label: {
                toolChip(
                    icon: "moon.zzz.fill",
                    title: sleepText,
                    highlighted: engine.sleepRemaining != nil
                )
            }
        }
    }

    private var sleepText: String {
        guard let remaining = engine.sleepRemaining, remaining > 0 else { return "定时" }
        let minutes = Int(remaining / 60)
        return minutes > 0 ? "\(minutes) 分" : "\(Int(remaining)) 秒"
    }

    private func toolChip(icon: String, title: String, highlighted: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(highlighted ? settings.accent : Theme.secondaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            GlassSurface(style: GlassStyle(intensity: 0.8, cornerRadius: 16)) { Color.clear }
        )
    }

    // MARK: - 队列

    private var queueSheet: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(engine.queue.enumerated()), id: \.element.id) { index, item in
                        TrackRow(
                            track: item,
                            isCurrent: engine.currentTrack?.id == item.id,
                            onTap: { engine.play(at: index) },
                            onToggleFavorite: nil
                        )
                    }
                }
                .pagePadding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { showsQueue = false }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
