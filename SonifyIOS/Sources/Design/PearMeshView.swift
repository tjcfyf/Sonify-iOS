import MetalKit
import SwiftUI

/// Pear Wall 的 iOS 简化版：全屏 Metal 着色器做"流体网格"背景。
///
/// Android 侧是 `pearmesh` 的多 pass 网格形变 + 多重模糊（GLSL，见上游 assets），
/// 这里先用单 pass 域扭曲（domain warp）复刻它的观感（流动、渐变、随音乐）。
/// 不追求逐像素一致，重点是低成本、低风险：`MTKView` 不可用时自动退回静态渐变。
struct PearMeshView: UIViewRepresentable {
    /// 三个基准色（一般来自封面主色 + 主题色）。
    var colors: [Color]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MTKView {
        let fallback = MTKView()
        fallback.isOpaque = false
        fallback.backgroundColor = .clear

        guard let device = MTLCreateSystemDefaultDevice() else { return fallback }

        let view = MTKView(frame: .zero, device: device)
        view.framebufferOnly = true
        view.isOpaque = false
        view.backgroundColor = .clear
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = 30
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)

        guard let renderer = PearMeshRenderer(device: device, view: view, colors: resolved(colors)) else {
            return fallback
        }
        context.coordinator.renderer = renderer
        view.delegate = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.renderer?.update(colors: resolved(colors))
    }

    private func resolved(_ colors: [Color]) -> [SIMD3<Float>] {
        let fallback: [Color] = [Color(hex: 0x2A1B4A), Color(hex: 0x0E2A46), Color(hex: 0x120B18)]
        return colors.enumerated().map { index, color in
            let ui = UIColor(color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
                return SIMD3<Float>(Float(r), Float(g), Float(b))
            }
            let base = UIColor(fallback[min(index, fallback.count - 1)])
            base.getRed(&r, green: &g, blue: &b, alpha: &a)
            return SIMD3<Float>(Float(r), Float(g), Float(b))
        }
    }

    final class Coordinator {
        var renderer: PearMeshRenderer?
    }
}

final class PearMeshRenderer: NSObject, MTKViewDelegate {

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue?
    private let pipeline: MTLRenderPipelineState?
    private var colors: [SIMD3<Float>]
    private let startedAt = CACurrentMediaTime()

    /// 注意：类的 failable init 必须在 return nil 之前给所有存储属性赋值，
    /// 所以这里把 queue / pipeline 声明成可选，失败时赋 nil 再返回。
    init?(device: MTLDevice, view: MTKView, colors: [SIMD3<Float>]) {
        self.device = device
        self.colors = colors
        self.commandQueue = device.makeCommandQueue()

        let source = PearMeshRenderer.shaderSource
        var state: MTLRenderPipelineState?
        if let library = try? device.makeLibrary(source: source, options: nil),
           let vertex = library.makeFunction(name: "pear_vertex"),
           let fragment = library.makeFunction(name: "pear_fragment") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = false
            state = try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        self.pipeline = state
        super.init()

        if state == nil { return nil }
    }

    func update(colors: [SIMD3<Float>]) {
        if colors.count == self.colors.count { self.colors = colors }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pipeline = pipeline,
              let commandQueue = commandQueue,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        var time = Float(CACurrentMediaTime() - startedAt)
        var c1 = colors[safe: 0] ?? SIMD3<Float>(0.16, 0.10, 0.28)
        var c2 = colors[safe: 1] ?? SIMD3<Float>(0.05, 0.16, 0.26)
        var c3 = colors[safe: 2] ?? SIMD3<Float>(0.07, 0.04, 0.09)

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
        encoder.setFragmentBytes(&c1, length: MemoryLayout<SIMD3<Float>>.size, index: 1)
        encoder.setFragmentBytes(&c2, length: MemoryLayout<SIMD3<Float>>.size, index: 2)
        encoder.setFragmentBytes(&c3, length: MemoryLayout<SIMD3<Float>>.size, index: 3)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VOut pear_vertex(uint vid [[vertex_id]]) {
        float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        float2 p = positions[vid];
        VOut out;
        out.position = float4(p, 0.0, 1.0);
        out.uv = p * 0.5 + 0.5;
        return out;
    }

    fragment float4 pear_fragment(VOut in [[stage_in]],
                                  constant float &uTime [[buffer(0)]],
                                  constant float3 &c1 [[buffer(1)]],
                                  constant float3 &c2 [[buffer(2)]],
                                  constant float3 &c3 [[buffer(3)]]) {
        float2 q = in.uv * 2.0 - 1.0;
        float t = uTime;

        // 域扭曲：两层不同频率的正余弦把平面"揉"成流动的网格。
        float2 warp = float2(
            sin(q.y * 2.6 + t * 0.55) + sin(q.x * 1.7 - t * 0.31),
            cos(q.x * 2.2 - t * 0.47) + cos(q.y * 1.5 + t * 0.26)
        );
        float2 p = q + warp * 0.13;

        float band = 0.5 + 0.5 * sin(p.x * 1.8 + p.y * 1.35 + t * 0.25);
        float sweep = smoothstep(-0.9, 0.9, p.y + 0.22 * sin(p.x * 2.1 + t * 0.18));

        float3 color = mix(c1, c2, clamp(band, 0.0, 1.0));
        color = mix(color, c3, clamp(sweep * 0.85, 0.0, 1.0));

        // 轻微网格线，模拟 Pear Wall 的 mesh 边界。
        float grid = smoothstep(0.42, 0.5, abs(fract(p.x * 2.0 + t * 0.05) - 0.5))
                   * smoothstep(0.42, 0.5, abs(fract(p.y * 2.0 - t * 0.04) - 0.5));
        color += grid * 0.035;

        color = clamp(color, 0.0, 1.0);
        return float4(color, 1.0);
    }
    """
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
