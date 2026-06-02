import XCTest
@testable import Jot

/// Covers the Recording Folder contract (CONTEXT.md → Recording Folder):
/// datestamp creation, artifact writes, and the title rename.
final class SessionStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sessionstore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: iso)!
    }

    func testCreatesDatestampFolder() throws {
        let store = try SessionStore(notesDirectory: root, startedAt: date("2026-05-31T14:30:00Z"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url.path))
        // Name is datestamp-only (local time, so just assert the shape, not the value).
        XCTAssertEqual(store.url.lastPathComponent.count, "yyyy-MM-dd HH-mm".count)
    }

    func testSecondSessionInSameMinuteGetsSuffix() throws {
        let when = date("2026-05-31T14:30:00Z")
        let first = try SessionStore(notesDirectory: root, startedAt: when)
        let second = try SessionStore(notesDirectory: root, startedAt: when)
        XCTAssertNotEqual(first.url, second.url)
        XCTAssertTrue(second.url.lastPathComponent.hasSuffix("(2)"))
    }

    func testWritesArtifacts() throws {
        let store = try SessionStore(notesDirectory: root, startedAt: Date())
        try store.writeTranscript("[00:01] User: hi")
        try store.writeNotes("## Summary\nA chat.")
        try store.writeMetadata(MeetingMetadata(
            sessionId: UUID(), startedAt: Date(), stoppedAt: nil, elapsedSeconds: 12,
            whisperModel: "ggml-small.en.bin", agentUsed: "Codex", generatedTitle: nil))

        XCTAssertEqual(try String(contentsOf: store.transcriptURL, encoding: .utf8), "[00:01] User: hi")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.notesURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.metadataURL.path))
    }

    func testRenameUsesTitleOnlyAndMovesArtifacts() throws {
        let store = try SessionStore(notesDirectory: root, startedAt: Date())
        try store.writeTranscript("x")
        try store.rename(toTitle: "Roadmap")

        XCTAssertEqual(store.url.lastPathComponent, "Roadmap", "no datestamp in the folder name")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.transcriptURL.path),
                      "artifacts move with the folder")
    }

    func testRenameToDuplicateTitleGetsSuffix() throws {
        let first = try SessionStore(notesDirectory: root, startedAt: date("2026-05-31T14:30:00Z"))
        try first.rename(toTitle: "Roadmap")
        let second = try SessionStore(notesDirectory: root, startedAt: date("2026-05-31T15:00:00Z"))
        try second.rename(toTitle: "Roadmap")

        XCTAssertEqual(first.url.lastPathComponent, "Roadmap")
        XCTAssertEqual(second.url.lastPathComponent, "Roadmap (2)")
    }

    func testRenameSanitizesIllegalCharactersAndCaps() {
        XCTAssertEqual(SessionStore.sanitizedTitle("a/b:c\nd"), "a b c d")
        XCTAssertEqual(SessionStore.sanitizedTitle("   spaced    out   "), "spaced out")
        XCTAssertEqual(SessionStore.sanitizedTitle(String(repeating: "x", count: 100)).count, 60)
    }

    func testRenameWithEmptyTitleThrows() throws {
        let store = try SessionStore(notesDirectory: root, startedAt: Date())
        XCTAssertThrowsError(try store.rename(toTitle: "  ///  ")) { error in
            XCTAssertEqual(error as? SessionStore.StoreError, .emptyTitle)
        }
    }
}
