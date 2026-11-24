import CoreImage
import SwiftUI
import UIKit

/// 封面取色（Android 侧用 AndroidX Palette，这里用 CIAreaAverage 便宜地拿主色）。
/// iOS 15 没有 `Palette` 等价 API，也用不上 k-means 那种重算法。
enum ArtworkPalette {

    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func averageColor(from data: Data?) -> Color? {
        guard let data = data,
              let image = UIImage(data: data),
              let cgImage = image.cgImage
        else { return nil }

        let input = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(
            name: "CIAreaAverage",
            parameters: [
                kCIInputImageKey: input,
                kCIInputExtentKey: CIVector(cgRect: input.extent),
            ]
        ), let output = filter.outputImage
        else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        var red = Double(bitmap[0]) / 255
        var green = Double(bitmap[1]) / 255
        var blue = Double(bitmap[2]) / 255

        // 纯均值常常偏灰，做一次简单的饱和提升，观感才像"封面取色"。
        let gray = (red + green + blue) / 3
        let boost = 1.35
        red = min(1, max(0, gray + (red - gray) * boost))
        green = min(1, max(0, gray + (green - gray) * boost))
        blue = min(1, max(0, gray + (blue - gray) * boost))

        return Color(red: red, green: green, blue: blue)
    }
}
