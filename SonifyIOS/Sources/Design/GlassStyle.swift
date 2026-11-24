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

    static let card = GlassStyle()
    static let panel = GlassStyle(intensity: 1.0, cornerRadius: Theme.panelRadius)
    static let chip = GlassStyle(intensity: 0.8, cornerRadius: 22)
}

/// 可调强度的模糊底。`intensity` 越小越透。
struct GlassBackground: UIViewRepresentable {
    var style: GlassStyle

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: style.material))
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear

        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) { [weak view] in
            view?.effect = nil
        }
        // 必须先 start 再 pause，fractionComplete 才会生效。
        animator.startAnimation()
        animator.pauseAnimation()
        animator.fractionComplete = CGFloat(1 - style.intensity)
        context.coordinator.animator = animator
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        let fraction = CGFloat(1 - style.intensity)
        guard let animator = context.coordinator.animator else { return }
        if abs(animator.fractionComplete - fraction) > 0.01 {
            animator.fractionComplete = fraction
        }
    }

    final class Coordinator {
        var animator: UIViewPropertyAnimator?
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
                    GlassBackground(style: style)
                    LinearGradient(
                        colors: [
                            style.tint.opacity(style.tintOpacity * 1.6),
                            style.tint.opacity(style.tintOpacity * 0.4),
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
