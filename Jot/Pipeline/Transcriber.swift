import Foundation

/// Converts a raw audio chunk into transcript segments. The only v1
/// implementation is `WhisperCppTranscriber`.
protocol Transcriber: Sendable {
    func transcribe(audioChunk: URL, source: AudioSource) async throws -> [TranscriptSegment]
}

enum TranscriberError: Error {
    case modelNotFound
    case notImplemented
}

/// Wraps a bundled `whisper-cli` binary invoked over `Process`. Stubbed for now
/// — wiring the binary, model download, and stdout parsing comes with the real
/// pipeline.
struct WhisperCppTranscriber: Transcriber {
    let modelURL: URL
    let binaryURL: URL

    func transcribe(audioChunk: URL, source: AudioSource) async throws -> [TranscriptSegment] {
        throw TranscriberError.notImplemented
    }
}
