import XCTest
@testable import Sonify

final class LibraryDeleteTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sonify-delete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testRemovesAudioLyricAndEmptyFolder() throws {
        let folder = root.appendingPathComponent("示例曲", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let audio = folder.appendingPathComponent("Sonify 演示曲.wav")
        let lyric = folder.appendingPathComponent("Sonify 演示曲.lrc")
        try Data("wav".utf8).write(to: audio)
        try Data("lrc".utf8).write(to: lyric)

        TrackFileRemoval.remove(audio: audio)

        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path), "音频没删掉")
        XCTAssertFalse(FileManager.default.fileExists(atPath: lyric.path), "同名歌词没删掉")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "空目录没清理")
    }

    func testKeepsFolderWhenOtherSongsRemain() throws {
        let folder = root.appendingPathComponent("曲库", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let a = folder.appendingPathComponent("a.wav")
        let b = folder.appendingPathComponent("b.wav")
        try Data("a".utf8).write(to: a)
        try Data("b".utf8).write(to: b)

        TrackFileRemoval.remove(audio: a)

        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path), "误删了别的歌")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testMissingFileDoesNotThrow() throws {
        let ghost = root.appendingPathComponent("不存在.wav")
        TrackFileRemoval.remove(audio: ghost)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path), "不存在的文件不该动到父目录")
    }
}
