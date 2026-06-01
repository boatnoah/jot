import XCTest
@testable import Jot

/// Fast, deterministic tests for the whisper-cli JSON → `TranscriptSegment`
/// mapping. No binary, no audio — just the parsing logic that's most likely to
/// have bugs (ms→seconds, elapsed-offset, trimming, non-speech filtering).
final class WhisperTranscriberTests: XCTestCase {
    func testParsesSegmentsWithElapsedOffset() throws {
        let json = Data("""
        { "transcription": [
            { "offsets": { "from": 0, "to": 3280 }, "text": " Let us ship the transcriber." },
            { "offsets": { "from": 3280, "to": 5000 }, "text": " [BLANK_AUDIO]" },
            { "offsets": { "from": 5000, "to": 7000 }, "text": "  I will handle QA.  " }
        ] }
        """.utf8)

        let segments = try WhisperCppTranscriber.parseSegments(
            from: json, source: .system, elapsedOffset: 100)

        // The [BLANK_AUDIO] marker is dropped.
        XCTAssertEqual(segments.count, 2)

        XCTAssertEqual(segments[0].source, .system)
        XCTAssertEqual(segments[0].startElapsed, 100.0, accuracy: 0.0001)
        XCTAssertEqual(segments[0].endElapsed, 103.28, accuracy: 0.0001)
        XCTAssertEqual(segments[0].text, "Let us ship the transcriber.")

        XCTAssertEqual(segments[1].startElapsed, 105.0, accuracy: 0.0001)
        XCTAssertEqual(segments[1].text, "I will handle QA.")
    }

    func testFiltersParentheticalNonSpeech() throws {
        let json = Data(#"{ "transcription": [ { "offsets": { "from": 0, "to": 500 }, "text": "(buzzing)" } ] }"#.utf8)
        let segments = try WhisperCppTranscriber.parseSegments(from: json, source: .microphone, elapsedOffset: 0)
        XCTAssertTrue(segments.isEmpty)
    }

    func testEmptyTranscription() throws {
        let json = Data(#"{ "transcription": [] }"#.utf8)
        let segments = try WhisperCppTranscriber.parseSegments(from: json, source: .microphone, elapsedOffset: 0)
        XCTAssertTrue(segments.isEmpty)
    }
}
