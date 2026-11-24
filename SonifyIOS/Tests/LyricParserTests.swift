import XCTest
@testable import Sonify

final class LyricParserTests: XCTestCase {

    func testLRCBasic() {
        let lrc = """
        [ti:Test]
        [00:12.30]Hello world
        [00:18.00]Second line
        """
        let entries = LyricParser.parseLRC(lrc)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].plainText, "Hello world")
        XCTAssertEqual(entries[0].startTime, 12300, accuracy: 1)
        XCTAssertEqual(entries[1].startTime, 18000, accuracy: 1)
        XCTAssertFalse(entries[0].isWordLevel)
    }

    /// KRC 词结束时间 = start + offset + duration，与 Android 逐词语义一致。
    func testKRCWordTiming() {
        let krc = """
        [12000,3000]<0,500,0>你<500,600,0>好<1100,900,0>世界
        """
        let entries = LyricParser.parseKRC(krc)
        XCTAssertEqual(entries.count, 1)
        guard let entry = entries.first else { return XCTFail("无歌词") }
        XCTAssertTrue(entry.isWordLevel)
        XCTAssertEqual(entry.spans.first?.time ?? 0, 12000, accuracy: 1)
        XCTAssertEqual(entry.spans[1].text, "你")
        XCTAssertEqual(entry.spans[1].time, 12500, accuracy: 1)
        XCTAssertEqual(entry.spans[2].time, 13100, accuracy: 1)
        XCTAssertEqual(entry.spans[3].time, 14000, accuracy: 1)
        XCTAssertEqual(entry.spans.last?.time ?? 0, 15000, accuracy: 1)
    }

    func testMetadataFiltered() {
        let krc = """
        [0,500]<0,500,0>作词：某某
        [2000,1000]<0,500,0>真<500,500,0>歌词
        """
        let entries = LyricParser.parseKRC(krc)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].plainText, "真歌词")
    }

    func testPlainTextFallback() {
        let text = "第一行\n第二行\n第三行"
        let entries = LyricParser.synthesizeFromPlainText(text, totalDuration: 30)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].startTime, 0, accuracy: 1)
        XCTAssertEqual(entries[1].startTime, 10000, accuracy: 1)
    }

    func testSpanProgressClamp() {
        let entry = LyricEntry(
            spans: [
                LyricSpan(time: 0, text: ""),
                LyricSpan(time: 1000, text: "字"),
                LyricSpan(time: 2000, text: ""),
            ],
            translation: nil,
            romanization: nil
        )
        XCTAssertEqual(spanProgress(in: entry, spanIndex: 1, timeMs: 500), 0.5, accuracy: 0.01)
        XCTAssertEqual(spanProgress(in: entry, spanIndex: 1, timeMs: -100), 0, accuracy: 0.01)
        XCTAssertEqual(spanProgress(in: entry, spanIndex: 1, timeMs: 5000), 1, accuracy: 0.01)
    }
}
