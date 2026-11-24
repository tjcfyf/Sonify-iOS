import SwiftUI

/// 设计常量集中处。Android 端把主题色、圆角、间距散在 `ui/theme` 多个文件里，
/// iOS 这边统一收口，改一处全 App 生效。
enum Theme {

    // MARK: - 主题色（对应 Android 11 种预设的近似取值）

    static let accents: [Color] = [
        Color(hex: 0xFF5A5F), // 珊瑚
        Color(hex: 0xFF9F0A), // 橙
        Color(hex: 0xFFD60A), // 黄
        Color(hex: 0x30D158), // 绿
        Color(hex: 0x32D74B), // 薄荷
        Color(hex: 0x40C8E0), // 青
        Color(hex: 0x64D2FF), // 天空
        Color(hex: 0x0A84FF), // 蓝
        Color(hex: 0x5E5CE6), // 靛
        Color(hex: 0xBF5AF2), // 紫
        Color(hex: 0xFF375F), // 玫红
    ]

    static let accentNames = [
        "珊瑚", "橙", "黄", "绿", "薄荷", "青",
        "天空", "蓝", "靛", "紫", "玫红",
    ]

    // MARK: - 基础色

    static let background = Color(hex: 0x08080C)
    static let surface = Color(hex: 0x141419)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.38)
    static let separator = Color.white.opacity(0.10)

    // MARK: - 几何

    /// 与 Android `DeviceRoundedCornerShape` 对齐：卡片 28，大面板 34，胶囊取高度一半。
    static let cardRadius: CGFloat = 28
    static let panelRadius: CGFloat = 34
    static let compactRadius: CGFloat = 16

    /// 玻璃描边：外层高光 + 内层暗线（README 里说的「iOS 27 双层立体玻璃描边」）。
    static let strokeHighlight = Color.white.opacity(0.34)
    static let strokeShadow = Color.black.opacity(0.16)

    static let pagePadding: CGFloat = 20
    static let sectionSpacing: CGFloat = 18
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

extension View {
    /// 连续曲率圆角（对应 Android Shapes 库的 ContinuousRoundedCorner）。
    func continuousCorner(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    func pagePadding() -> some View {
        padding(.horizontal, Theme.pagePadding)
    }
}

/// 主题色由设置驱动，所有页面从这里取，避免每页自己读 UserDefaults。
struct AccentEnvironment: EnvironmentKey {
    static let defaultValue: Color = Theme.accents[7]
}

extension EnvironmentValues {
    var accent: Color {
        get { self[AccentEnvironment.self] }
        set { self[AccentEnvironment.self] = newValue }
    }
}
