import SwiftUI

/// 设置页。Android 有 account / audio / library / performance / storage 等 7 个分区，
/// M0 只保留与已实现能力相关的项，其余分区留到对应里程碑再加。
struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var engine: PlayerEngine

    @State private var showRescanDone = false
    @State private var showClearConfirm = false

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    appearanceSection
                    playbackSection
                    lyricSection
                    storageSection
                    aboutSection
                }
                .pagePadding()
                .padding(.top, 6)
                .padding(.bottom, 130)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        sectionCard(title: "外观") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("玻璃模糊强度")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.primaryText)
                        Spacer()
                        Text(String(format: "%.0f%%", settings.glassIntensity * 100))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundColor(settings.accent)
                    }
                    Slider(value: $settings.glassIntensity, in: 0.1...1.0)
                        .tint(settings.accent)
                    Text("数值越低越通透；Android 端同一参数对应 Haze 的模糊档位。")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.tertiaryText)
                }

                Divider().background(Theme.separator)

                toggleRow(title: "流体网格背景（实验）", isOn: $settings.pearMeshEnabled)
                Text("Metal 单 pass 域扭曲，复刻 Android 端 Pear Wall 的流动观感；关掉即回到封面模糊背景。")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().background(Theme.separator)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("主题色")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.primaryText)
                        Spacer()
                        Text(settings.accentName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.secondaryText)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                        ForEach(Array(Theme.accents.enumerated()), id: \.offset) { index, color in
                            Button {
                                settings.accentIndex = index
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(Color.white.opacity(settings.accentIndex == index ? 0.9 : 0.12), lineWidth: settings.accentIndex == index ? 2 : 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 播放

    private var playbackSection: some View {
        sectionCard(title: "播放") {
            VStack(spacing: 12) {
                HStack {
                    Text("默认倍速")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.primaryText)
                    Spacer()
                    Menu {
                        ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                            Button(String(format: "%.2fx", rate)) {
                                settings.defaultRate = rate
                                engine.setRate(Float(rate))
                            }
                        }
                    } label: {
                        Text(String(format: "%.2fx", settings.defaultRate))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundColor(settings.accent)
                    }
                }
                Divider().background(Theme.separator)
                toggleRow(title: "冷启动恢复上次播放", isOn: $settings.autoRestorePlayback)
                Divider().background(Theme.separator)
                toggleRow(title: "播放时追加到队列", isOn: $settings.appendQueueOnPlay)
            }
        }
    }

    // MARK: - 歌词

    private var lyricSection: some View {
        sectionCard(title: "歌词") {
            VStack(spacing: 12) {
                toggleRow(title: "显示翻译 / 罗马音", isOn: $settings.showTranslation)
                Divider().background(Theme.separator)
                toggleRow(
                    title: "锁屏显示当前歌词行",
                    isOn: Binding(
                        get: { settings.backgroundLyricLine },
                        set: { enabled in
                            settings.backgroundLyricLine = enabled
                            NowPlayingCenter.lyricLineEnabled = enabled
                            engine.lockScreenLyricEnabled = enabled
                            engine.refreshLockScreenInfo()
                        }
                    )
                )
                Text("iOS 非越狱无法实现 Android 的状态栏歌词（Hook 方案）；这里把当前歌词行写进锁屏副标题，是唯一合法途径。")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 存储

    private var storageSection: some View {
        sectionCard(title: "资料库") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("已扫描歌曲")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.primaryText)
                    Spacer()
                    Text("\(library.tracks.count) 首")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.secondaryText)
                }
                HStack {
                    Text("目录")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.primaryText)
                    Spacer()
                    Text("App/Documents")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.tertiaryText)
                }
                Button {
                    Task {
                        await library.refresh()
                        showRescanDone = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .bold))
                        Text(library.isScanning ? "正在扫描…" : "重新扫描")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(settings.accent)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)

                Button {
                    showClearConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .bold))
                        Text("清除全部本地歌曲")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(Theme.accents[0])
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .disabled(library.tracks.isEmpty)
                .opacity(library.tracks.isEmpty ? 0.4 : 1)
            }
        }
        .alert("删除全部本地歌曲？", isPresented: $showClearConfirm) {
            Button("全部删除", role: .destructive) {
                library.deleteAllLocalTracks()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("共 \(library.tracks.count) 首，文件与同名歌词都会删掉，不可恢复。")
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        sectionCard(title: "关于") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Sonify for iOS")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.primaryText)
                    Spacer()
                    Text("M0 · 0.1.0")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.tertiaryText)
                }
                Text("上游 Android 项目基于 GPL-3.0，本移植同样以 GPL-3.0 发布；保留原作者署名与 Pear Wall / NexioSchedule 的 NOTICE。")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("在线曲库")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.secondaryText)
                    Spacer()
                    Text("待接入（M3）")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.tertiaryText)
                }
            }
        }
    }

    // MARK: - 组件

    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.tertiaryText)
                .padding(.leading, 4)
            GlassSurface(style: settings.glassStyle) {
                content()
                    .padding(16)
            }
        }
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.primaryText)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(settings.accent)
        }
    }
}
