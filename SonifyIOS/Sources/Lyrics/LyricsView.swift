import SwiftUI

/// 卡拉 OK 歌词视图。
/// Android 是 Compose + `YosLyricView`/`YosLyricGeometry` 手算几何；iOS 这边用
/// "逐词叠加 + 左侧裁切"实现同一效果：底层暗色文字，上层亮色文字被宽度等于进度的矩形遮罩。
struct LyricsView: View {
    let entries: [LyricEntry]
    /// 当前播放位置（毫秒）。来自 PlayerEngine 的 `currentTime * 1000`。
    let timeMs: Float
    var accent: Color = Theme.accents[7]
    var showTranslation: Bool = true
    /// 字号倍率（设置页滑杆），0.85…1.4。
    var scale: CGFloat = 1

    private func mainSize(_ isActive: Bool) -> CGFloat { (isActive ? 26 : 19) * scale }
    private func transSize(_ isActive: Bool) -> CGFloat { (isActive ? 15 : 13) * scale }

    private var activeIndex: Int {
        entries.currentIndex(at: timeMs)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24 * scale) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        row(entry, isActive: index == activeIndex)
                            .id(index)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 140)
                .padding(.horizontal, 24)
            }
            .onChange(of: activeIndex) { newValue in
                guard entries.indices.contains(newValue) else { return }
                NowPlayingCenter.currentLyricLine = entries[newValue].plainText
                withAnimation(.easeInOut(duration: 0.32)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onAppear {
                if entries.indices.contains(activeIndex) {
                    NowPlayingCenter.currentLyricLine = entries[activeIndex].plainText
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: LyricEntry, isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.isWordLevel {
                wordLine(entry, isActive: isActive)
            } else {
                Text(entry.plainText)
                    .font(.system(size: mainSize(isActive), weight: isActive ? .bold : .semibold))
                    .foregroundColor(isActive ? Theme.primaryText : Theme.tertiaryText)
                    .blur(radius: isActive ? 0 : 0.3)
            }

            if showTranslation, let translation = entry.translation, !translation.isEmpty {
                Text(translation)
                    .font(.system(size: transSize(isActive), weight: .medium))
                    .foregroundColor(isActive ? Theme.secondaryText : Theme.tertiaryText)
            }

            if showTranslation, let romanization = entry.romanization, !romanization.isEmpty {
                Text(romanization)
                    .font(.system(size: 12 * scale, weight: .regular))
                    .foregroundColor(Theme.tertiaryText)
            }
        }
        .scaleEffect(isActive ? 1 : 0.94, anchor: .leading)
        .opacity(isActive ? 1 : 0.55)
        .animation(.easeInOut(duration: 0.28), value: isActive)
    }

    /// 逐词高亮：每个词独立进度，避免整行"一刀切"式的线性扫色。
    private func wordLine(_ entry: LyricEntry, isActive: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(1..<max(1, entry.spans.count - 1), id: \.self) { index in
                let word = entry.spans[index]
                let progress = isActive
                    ? spanProgress(in: entry, spanIndex: index, timeMs: timeMs)
                    : 0

                Text(word.text)
                    .font(.system(size: mainSize(isActive), weight: isActive ? .bold : .semibold))
                    .foregroundColor(isActive ? Theme.primaryText.opacity(0.28) : Theme.tertiaryText)
                    .overlay(
                        Text(word.text)
                            .font(.system(size: mainSize(isActive), weight: isActive ? .bold : .semibold))
                            .foregroundColor(accent)
                            .mask(
                                GeometryReader { geometry in
                                    Rectangle()
                                        .frame(
                                            width: geometry.size.width * CGFloat(progress),
                                            height: geometry.size.height
                                        )
                                }
                            )
                            .allowsHitTesting(false)
                    )
                    .animation(.linear(duration: 0.25), value: progress)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}
