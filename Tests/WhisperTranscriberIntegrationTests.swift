import XCTest
@testable import Jot

/// End-to-end check of the real `WhisperCppTranscriber`: runs `whisper-cli` on a
/// bundled 16 kHz WAV fixture and maps the output. Needs the binary on PATH and
/// the model on disk, and takes a few seconds, so it's opt-in — set
/// `JOT_RUN_WHISPER_TESTS=1` to run it.
final class WhisperTranscriberIntegrationTests: XCTestCase {
    func testTranscribesFixtureWithElapsedOffset() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["JOT_RUN_WHISPER_TESTS"] == "1",
            "Set JOT_RUN_WHISPER_TESTS=1 to run the real whisper-cli integration test.")

        let transcriber = try XCTUnwrap(
            WhisperCppTranscriber.makeDefault(),
            "whisper-cli not found on PATH, or the model isn't downloaded")

        let wav = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "whisper_sample", withExtension: "wav"),
            "fixture WAV missing from the test bundle")

        let segments = try await transcriber.transcribe(
            audioChunk: wav, source: .microphone, elapsedOffset: 10)

        XCTAssertFalse(segments.isEmpty, "expected at least one segment")
        XCTAssertEqual(segments[0].source, .microphone)
        // Offset is applied: the fixture starts at 0, shifted by 10s.
        XCTAssertGreaterThanOrEqual(segments[0].startElapsed, 10)
        let text = segments.map(\.text).joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("friday") || text.contains("ship") || text.contains("transcriber"),
                      "unexpected transcript: \(text)")
    }
}
