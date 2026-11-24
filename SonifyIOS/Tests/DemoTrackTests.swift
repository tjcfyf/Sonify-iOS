import XCTest
@testable import Sonify

final class DemoTrackTests: XCTestCase {

    func testDemoWaveIsGenerated() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sonify-demo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try XCTUnwrap(DemoTrackFactory.ensure(in: directory), "演示曲生成失败")

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        // 15 秒 44.1kHz 16bit 单声道 ≈ 1.32 MB
        XCTAssertGreaterThan(size, 1_200_000, "WAV 太小，说明没写进 PCM")

        let lrcURL = url.deletingPathExtension().appendingPathExtension("lrc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: lrcURL.path))

        let lrc = try String(contentsOf: lrcURL, encoding: .utf8)
        let entries = LyricParser.parse(text: lrc)
        XCTAssertEqual(entries.count, 5, "逐词 LRC 应该解析出 5 行")
        XCTAssertTrue(entries.allSatisfy { $0.isWordLevel }, "演示歌词应该是词级时间轴")
    }
}
