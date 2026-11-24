import SwiftUI

/// 封面视图：没有内嵌封面时给一个基于标题哈希的渐变色块，避免整页"空白灰"。
struct ArtworkView: View {
    let track: Track?
    var cornerRadius: CGFloat = Theme.compactRadius

    var body: some View {
        ZStack {
            if let data = track?.artworkData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: placeholderColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white.opacity(0.55))
            }
        }
        .continuousCorner(cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .clipped()
    }

    private var placeholderColors: [Color] {
        guard let title = track?.title, !title.isEmpty else {
            return [Color(hex: 0x2C2C34), Color(hex: 0x141419)]
        }
        var hash: UInt32 = 5381
        for scalar in title.unicodeScalars {
            hash = hash &* 33 &+ scalar.value
        }
        let hue = Double(hash % 360) / 360
        return [
            Color(hue: hue, saturation: 0.45, brightness: 0.48),
            Color(hue: hue + 0.08, saturation: 0.38, brightness: 0.22),
        ]
    }
}
