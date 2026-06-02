import XCTest
@testable import Jot

/// Pins the transcript ordering and formatting contract the notes agent and the
/// user both depend on (CONTEXT.md → Transcript).
final class TranscriptBuilderTests: XCTestCase {
    private func seg(_ source: AudioSource, _ start: TimeInterval, _ text: String) -> TranscriptSegment {
        TranscriptSegment(source: source, startElapsed: start, endElapsed: start + 1, text: text)
    }

    func testEmptyRendersEmptyString() {
        XCTAssertEqual(TranscriptBuilder.render([]), "")
    }

    func testSortsByElapsedAndTagsSpeakers() {
        let out = TranscriptBuilder.render([
            seg(.system, 5, "second"),
            seg(.microphone, 1, "first"),
        ])
        XCTAssertEqual(out, "[00:01] User: first\n[00:05] Others: second")
    }

    func testTieWithin500msPutsUserBeforeOthers() {
        // Others starts slightly earlier, but within the 500 ms window User wins.
        let out = TranscriptBuilder.render([
            seg(.system, 10.0, "others"),
            seg(.microphone, 10.4, "user"),
        ])
        XCTAssertEqual(out, "[00:10] User: user\n[00:10] Others: others")
    }

    func testGapBeyond500msKeepsChronologicalOrder() {
        // 600 ms apart — outside the window, so earlier timestamp wins.
        let out = TranscriptBuilder.render([
            seg(.microphone, 10.6, "user"),
            seg(.system, 10.0, "others"),
        ])
        XCTAssertEqual(out, "[00:10] Others: others\n[00:10] User: user")
    }

    func testFormatsHoursOncePastAnHour() {
        XCTAssertEqual(TranscriptBuilder.timestamp(0), "00:00")
        XCTAssertEqual(TranscriptBuilder.timestamp(75), "01:15")
        XCTAssertEqual(TranscriptBuilder.timestamp(3661), "1:01:01")
    }
}
