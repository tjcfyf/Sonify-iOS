import Combine
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: SettingsStore

    @StateObject private var router = TabRouter()
    @State private var showsPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $router.selected) {
                HomeView()
                    .tabItem { Label("首页", systemImage: "house.fill") }
                    .tag(TabRouter.Tab.home)
                LibraryView()
                    .tabItem { Label("资料库", systemImage: "music.note.list") }
                    .tag(TabRouter.Tab.library)
                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape.fill") }
                    .tag(TabRouter.Tab.settings)
            }
            .accentColor(settings.accent)

            if engine.currentTrack != nil {
                MiniPlayerBar { showsPlayer = true }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 52)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.accent, settings.accent)
        .environmentObject(router)
        .sheet(isPresented: Binding(
            get: { showsPlayer || router.presentPlayer },
            set: { newValue in
                showsPlayer = newValue
                if !newValue { router.presentPlayer = false }
            }
        )) {
            NowPlayingView()
                .environmentObject(engine)
                .environmentObject(settings)
                .environmentObject(library)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            engine.persistState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            engine.persistState()
        }
        .onAppear {
            NowPlayingCenter.lyricLineEnabled = settings.backgroundLyricLine
            engine.lockScreenLyricEnabled = settings.backgroundLyricLine
            library.bootstrapIfNeeded()
            engine.bootstrapIfNeeded()
            if settings.autoRestorePlayback {
                engine.restoreLastSession()
            }
        }
    }
}

/// 底部迷你播放器（对应 Android 的底栏 NowPlaying 条）。
struct MiniPlayerBar: View {
    @EnvironmentObject private var engine: PlayerEngine
    @EnvironmentObject private var settings: SettingsStore

    var onTap: () -> Void

    var body: some View {
        GlassSurface(style: GlassStyle(intensity: 0.96, cornerRadius: 24)) {
            HStack(spacing: 12) {
                ArtworkView(track: engine.currentTrack, cornerRadius: 12)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.currentTrack?.title ?? "")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.primaryText)
                        .lineLimit(1)
                    Text(engine.currentTrack?.artist ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button(action: engine.togglePlayPause) {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Theme.primaryText)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: engine.next) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                        .frame(width: 36, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}
