import Foundation

/// Renders merged `TranscriptSegment`s into the durable `transcript.md`
/// (CONTEXT.md → Transcript): one timestamped, speaker-tagged line per segment,
/// in session-elapsed time. Pure and order-defining, so it's unit-testable
/// without any audio or whisper.
enum TranscriptBuilder {
    /// Sort segments and render one line each: `[mm:ss] User: text`.
    ///
    /// Ordering rule (CONTEXT.md → Transcript): primarily by `startElapsed`;
    /// for segments within 500 ms of each other, `User` (microphone) is placed
    /// before `Others` (system) so a question and its answer read naturally even
    /// when whisper's chunk-relative offsets jitter slightly across streams.
    static func render(_ segments: [TranscriptSegment]) -> String {
        let ordered = segments.sorted { a, b in
            if a.source != b.source, abs(a.startElapsed - b.startElapsed) <= 0.5 {
                return a.source == .microphone   // User before Others within the window
            }
            return a.startElapsed < b.startElapsed
        }
        return ordered
            .map { "[\(timestamp($0.startElapsed))] \($0.source.speakerTag): \($0.text)" }
            .joined(separator: "\n")
    }

    /// Elapsed seconds as `mm:ss`, widening to `h:mm:ss` once past an hour.
    static func timestamp(_ elapsed: TimeInterval) -> String {
        let total = Int(max(0, elapsed).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
