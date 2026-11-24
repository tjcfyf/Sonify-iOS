import AVFoundation
import Foundation

/// 演示曲：没有本地音乐时也能验证播放内核、歌词与视觉。
/// 纯本地生成，不联网、不带版权素材——一段 15 秒的合成旋律 + 逐词时间轴 LRC。
enum DemoTrackFactory {

    static let folderName = "示例曲"
    static let baseName = "Sonify 演示曲"

    @discardableResult
    static func ensure(in documents: URL) -> URL? {
        let folder = documents.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

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

    // MARK: - 音频

    private static func writeWave(to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]

        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let format = AVAudioFormat(settings: settings) else { return }

        let sampleRate = 44100.0
        let seconds = 15.0
        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.int16ChannelData?[0]
        else { return }
        buffer.frameLength = frameCount

        // D 大调五声音阶，四个小节；每 1.5 秒换一组音，避免机械感。
        let notes: [Double] = [587.33, 659.25, 783.99, 880.0, 783.99, 659.25, 587.33, 493.88, 587.33, 783.99]
        let total = Int(frameCount)

        for index in 0..<total {
            let t = Double(index) / sampleRate
            let noteIndex = min(notes.count - 1, Int(t / 1.5))
            let frequency = notes[noteIndex]
            // 每个音符内部做 attack/decay 包络，听起来像"有音符"而不是持续正弦。
            let local = t.truncatingRemainder(dividingBy: 1.5)
            let attack = min(1, local / 0.12)
            let decay = max(0, 1 - pow(local / 1.5, 2.2))
            let envelope = attack * decay

            let tone = sin(2 * .pi * frequency * t) * 0.55
                + sin(2 * .pi * frequency * 2 * t) * 0.16
            let bass = sin(2 * .pi * (frequency / 2) * t) * 0.12
            let sample = (tone + bass) * envelope * 0.55

            channel[index] = Int16(max(-1, min(1, sample)) * 32700)
        }

        try file.write(from: buffer)
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
