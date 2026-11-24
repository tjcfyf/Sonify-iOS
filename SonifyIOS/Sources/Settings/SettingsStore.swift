import Combine
import SwiftUI

/// 设置。Android 对应 `YosDataSaver` + `SettingOption` 的各个开关。
/// 这里刻意不用 `@AppStorage`：它面向 View 声明周期，在 ObservableObject 里不会触发
/// `objectWillChange`，改成 `@Published + didSet` 手写一轮。
final class SettingsStore: ObservableObject {

    static let shared = SettingsStore()

    enum Key {
        static let glassIntensity = "settings.glassIntensity"
        static let accentIndex = "settings.accentIndex"
        static let showTranslation = "settings.showTranslation"
        static let autoRestorePlayback = "settings.autoRestorePlayback"
        static let backgroundLyricLine = "settings.backgroundLyricLine"
        static let appendQueueOnPlay = "settings.appendQueueOnPlay"
        static let defaultRate = "settings.defaultRate"
        static let pearMeshEnabled = "settings.pearMeshEnabled"
    }

    @Published var glassIntensity: Double { didSet { store(glassIntensity, Key.glassIntensity) } }
    @Published var accentIndex: Int { didSet { store(accentIndex, Key.accentIndex) } }
    @Published var showTranslation: Bool { didSet { store(showTranslation, Key.showTranslation) } }
    @Published var autoRestorePlayback: Bool { didSet { store(autoRestorePlayback, Key.autoRestorePlayback) } }
    @Published var backgroundLyricLine: Bool { didSet { store(backgroundLyricLine, Key.backgroundLyricLine) } }
    @Published var appendQueueOnPlay: Bool { didSet { store(appendQueueOnPlay, Key.appendQueueOnPlay) } }
    @Published var defaultRate: Double { didSet { store(defaultRate, Key.defaultRate) } }
    @Published var pearMeshEnabled: Bool { didSet { store(pearMeshEnabled, Key.pearMeshEnabled) } }

    var accent: Color {
        Theme.accents[min(max(0, accentIndex), Theme.accents.count - 1)]
    }

    var accentName: String {
        Theme.accentNames[min(max(0, accentIndex), Theme.accentNames.count - 1)]
    }

    var glassStyle: GlassStyle {
        GlassStyle(intensity: glassIntensity)
    }

    private init() {
        let defaults = UserDefaults.standard
        glassIntensity = defaults.object(forKey: Key.glassIntensity) as? Double ?? 0.92
        accentIndex = defaults.object(forKey: Key.accentIndex) as? Int ?? 7
        showTranslation = defaults.object(forKey: Key.showTranslation) as? Bool ?? true
        autoRestorePlayback = defaults.object(forKey: Key.autoRestorePlayback) as? Bool ?? true
        backgroundLyricLine = defaults.object(forKey: Key.backgroundLyricLine) as? Bool ?? true
        appendQueueOnPlay = defaults.object(forKey: Key.appendQueueOnPlay) as? Bool ?? false
        defaultRate = defaults.object(forKey: Key.defaultRate) as? Double ?? 1.0
        pearMeshEnabled = defaults.object(forKey: Key.pearMeshEnabled) as? Bool ?? false
    }

    private func store(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
