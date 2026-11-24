import SwiftUI
import UIKit

/// iOS 15 版"液态玻璃"。
///
/// Android 侧是 Haze(2.1.0) + Backdrop：实时背景采样 → 多层高斯 → 材质叠加 → 描边。
/// iOS 15 没有 `.glassEffect()`（那是 iOS 26 的 API），这里用三件套近似：
///   1. `UIVisualEffectView` + `UIViewPropertyAnimator.fractionComplete` 实现**可调强度**的材质模糊；
///   2. 上层叠加极低 alpha 的白色渐变（上亮下暗），模拟玻璃厚度；
///   3. 双层描边：外层高光、内层暗线，配合连续曲率圆角。
///
struct GlassStyle: Equatable {
    /// 0 = 完全透明，1 = 材质原始强度。对应 Android 设置里"全局玻璃模糊强度"。
    var intensity: Double = 0.92
    var cornerRadius: CGFloat = Theme.cardRadius
    var material: UIBlurEffect.Style = .systemUltraThinMaterial
    var tint: Color = .white
    var tintOpacity: Double = 0.07
    var stroke: Bool = true

    /// 强度 → 材质档位（iOS 15 只能选档，不能连续调）。
    var resolvedMaterial: UIBlurEffect.Style {
        if intensity >= 0.88 { return .systemThinMaterial }
        if intensity >= 0.55 { return .systemUltraThinMaterial }
        return .systemUltraThinMaterial
    }

    static let card = GlassStyle()
    static let panel = GlassStyle(intensity: 1.0, cornerRadius: Theme.panelRadius)
    static let chip = GlassStyle(intensity: 0.8, cornerRadius: 22)
}

/// 模糊底。iOS 15 上**不使用** `UIViewPropertyAnimator` 调 `UIVisualEffectView` 强度：
/// 那种写法要求视图已进入 window，启动期批量创建时容易触发断言直接闪退。
/// 这里改成按强度切换材质档位 + 叠加层控制透明度，牺牲一点"连续可调"，换启动稳定。
struct GlassBackground: UIViewRepresentable {
    var style: GlassStyle

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style.material))
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        context.coordinator.material = style.material
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        // UIBlurEffect 没有公开的 style 属性，自己记一份，避免每帧重建 effect。
        guard context.coordinator.material != style.material else { return }
        context.coordinator.material = style.material
        uiView.effect = UIBlurEffect(style: style.material)
    }

    final class Coordinator {
        var material: UIBlurEffect.Style?
    }
}

/// 玻璃卡片容器：模糊 + 染色 + 厚度渐变 + 双层描边。
struct GlassSurface<Content: View>: View {
    var style: GlassStyle
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                ZStack {
                    GlassBackground(
                        style: GlassStyle(
                            intensity: style.intensity,
                            cornerRadius: style.cornerRadius,
                            material: style.resolvedMaterial,
                            tint: style.tint,
                            tintOpacity: style.tintOpacity,
                            stroke: style.stroke
                        )
                    )
                    LinearGradient(
                        colors: [
                            style.tint.opacity(style.tintOpacity * 1.6 * style.intensity),
                            style.tint.opacity(style.tintOpacity * 0.4 * style.intensity),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
            .overlay(strokeOverlay)
            .compositingGroup()
    }

    @ViewBuilder
    private var strokeOverlay: some View {
        if style.stroke {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .strokeBorder(Theme.strokeHighlight, lineWidth: 1)
                .overlay(
                    RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                        .inset(by: 1.5)
                        .strokeBorder(Theme.strokeShadow, lineWidth: 1)
                )
        }
    }
}

/// 圆形玻璃按钮（对应 Android 顶栏玻璃圆钮）。
struct GlassCircleButton: View {
    let systemName: String
    var size: CGFloat = 42
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassSurface(style: GlassStyle(intensity: 0.9, cornerRadius: size / 2)) {
                Image(systemName: systemName)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundColor(Theme.primaryText)
                    .frame(width: size, height: size)
            }
        }
        .buttonStyle(GlassPressStyle())
    }
}

struct GlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// 顶栏渐进模糊：滚动偏移 0→1 时，顶栏从全透到全模糊。对应 Android「渐进模糊顶栏」。
struct ProgressiveGlassHeader<Content: View>: View {
    var progress: Double
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                GlassSurface(
                    style: GlassStyle(
                        intensity: max(0.05, min(1, progress)),
                        cornerRadius: 26
                    )
                ) { Color.clear }
            )
    }
}
