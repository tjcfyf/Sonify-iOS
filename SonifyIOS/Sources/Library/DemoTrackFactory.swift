import AVFoundation
import Foundation

/// 演示曲：没有本地音乐时也能验证播放内核、歌词与视觉。
/// 纯本地生成，不联网、不带版权素材——一段 15 秒的合成旋律 + 逐词时间轴 LRC。
///
/// 这里**手写 WAV 字节**，不用 `AVAudioFile.write(from:)`。
/// 原因：`AVAudioFile.write(from:)` 要求 buffer 的格式等于 `processingFormat`
/// （通常是 deinterleaved Float32）；用 `settings` 造 buffer 会抛出 ObjC 异常
/// （`AVAudioFile.mm` 的 format mismatch），Swift 的 do/catch 捕获不了，
/// 表现出来就是"点一下生成就闪退"。
enum DemoTrackFactory {

    static let folderName = "示例曲"
    static let baseName = "Sonify 演示曲"
    static let duration: Double = 15

    @discardableResult
    static func ensure(in documents: URL) -> URL? {
        let folder = documents.appendingPathComponent(folderName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let wavURL = folder.appendingPathComponent("\(baseName).wav")
        let lrcURL = folder.appendingPathComponent("\(baseName).lrc")

        if !FileManager.default.fileExists(atPath: wavURL.path) {
            do {
                try writeWave(to: wavURL)
            } catch {
                return nil
            }
        }
        try? lyrics.write(to: lrcURL, atomically: true, encoding: .utf8)
        return wavURL
    }

    // MARK: - 音频（手写 PCM WAV）

    private static func writeWave(to url: URL) throws {
        let sampleRate = 44_100
        let channels = 1
        let bitsPerSample = 16
        let frames = Int(Double(sampleRate) * duration)

        var samples = [Int16](repeating: 0, count: frames)
        // D 大调五声音阶；每个音 1.5 秒，带 attack/decay 包络。
        let notes: [Double] = [587.33, 659.25, 783.99, 880.0, 783.99, 659.25, 587.33, 493.88, 587.33, 783.99]

        for index in 0..<frames {
            let t = Double(index) / Double(sampleRate)
            let noteIndex = min(notes.count - 1, Int(t / 1.5))
            let frequency = notes[noteIndex]
            let local = t.truncatingRemainder(dividingBy: 1.5)
            let attack = min(1, local / 0.12)
            let decay = max(0, 1 - pow(local / 1.5, 2.2))
            let envelope = attack * decay

            let tone = sin(2 * .pi * frequency * t) * 0.55
                + sin(2 * .pi * frequency * 2 * t) * 0.16
            let bass = sin(2 * .pi * (frequency / 2) * t) * 0.12
            var sample = (tone + bass) * envelope * 0.55
            if !sample.isFinite { sample = 0 }
            sample = max(-1, min(1, sample))
            samples[index] = Int16(sample * 32_000)
        }

        var data = Data()
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        appendUInt32(UInt32(36 + frames * channels * bitsPerSample / 8), to: &data)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20]) // "fmt "
        appendUInt32(16, to: &data)
        appendUInt16(1, to: &data) // PCM
        appendUInt16(UInt16(channels), to: &data)
        appendUInt32(UInt32(sampleRate), to: &data)
        appendUInt32(UInt32(sampleRate * channels * bitsPerSample / 8), to: &data)
        appendUInt16(UInt16(channels * bitsPerSample / 8), to: &data)
        appendUInt16(UInt16(bitsPerSample), to: &data)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        appendUInt32(UInt32(frames * channels * bitsPerSample / 8), to: &data)

        var pcm = Data(capacity: frames * 2)
        for sample in samples {
            appendUInt16(UInt16(bitPattern: sample), to: &pcm)
        }
        data.append(pcm)

        try data.write(to: url, options: .atomic)
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    // MARK: - 歌词（LRC + 词级时间）

    /// 逐词写法：`<相对行起点的偏移(ms),该词时长(ms)>词`。
    /// 与 Android 端 LRC 词级语义一致（词高亮结束 = 行起点 + 偏移 + 时长）。
    private static let lyrics = """
    [00:00.60]<0,300>Sonify <300,400>演示 <700,500>曲
    [00:03.00]<0,260>这 <260,420>是 <680,380>一 <1060,700>段自动生成的旋律
    [00:06.00]<0,300>用 <300,400>来 <700,500>检查 <1200,600>播放与歌词
    [00:09.00]<0,280>逐 <280,420>词 <700,520>高亮 <1220,600>是否对齐
    [00:12.00]<0,300>拖 <300,300>动 <600,300>进 <900,300>度 <1200,900>条看看
    """
}
