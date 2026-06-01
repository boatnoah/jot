import Foundation

/// Converts a raw audio chunk into transcript segments. The only v1
/// implementation is `WhisperCppTranscriber`.
///
/// `elapsedOffset` is the total non-paused session time that preceded this
/// chunk (CONTEXT.md → Chunk); the transcriber adds it to whisper's
/// chunk-relative timestamps so the returned segments are already in
/// session-elapsed time.
protocol Transcriber: Sendable {
    func transcribe(
        audioChunk: URL,
        source: AudioSource,
        elapsedOffset: TimeInterval
    ) async throws -> [TranscriptSegment]
}

enum TranscriberError: Error, Equatable {
    case modelNotFound
    case binaryNotFound
    case transcriptionFailed(String)
    case notImplemented
}

/// Wraps the whisper.cpp `whisper-cli` binary over `ProcessRunner`. Invokes it
/// per chunk with JSON output, then maps whisper's millisecond offsets to
/// session-elapsed `TranscriptSegment`s. Non-speech markers whisper emits for
/// silence (e.g. `[BLANK_AUDIO]`) are dropped, so a silent chunk yields nothing.
struct WhisperCppTranscriber: Transcriber {
    var modelURL: URL
    var binaryURL: URL
    var timeout: Duration = .seconds(120)

    func transcribe(
        audioChunk: URL,
        source: AudioSource,
        elapsedOffset: TimeInterval
    ) async throws -> [TranscriptSegment] {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw TranscriberError.modelNotFound
        }
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            throw TranscriberError.binaryNotFound
        }

        // whisper-cli writes "<prefix>.json" with -oj/-of.
        let outputPrefix = FileManager.default.temporaryDirectory
            .appendingPathComponent("jot-whisper-\(UUID().uuidString)")
        let jsonURL = outputPrefix.appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let result = try await ProcessRunner.run(
            executableURL: binaryURL,
            arguments: [
                "-m", modelURL.path,
                "-f", audioChunk.path,
                "-oj",                       // JSON output
                "-of", outputPrefix.path,    // output file prefix
                "-np",                       // no progress prints
            ],
            timeout: timeout)

        guard result.exitCode == 0 else {
            let detail = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TranscriberError.transcriptionFailed(
                detail.isEmpty ? "whisper-cli exited with code \(result.exitCode)." : detail)
        }

        let data = try Data(contentsOf: jsonURL)
        return try Self.parseSegments(from: data, source: source, elapsedOffset: elapsedOffset)
    }

    /// Pure mapping from whisper-cli JSON to session-elapsed segments. Separated
    /// out so it's unit-testable without running the binary.
    static func parseSegments(
        from data: Data,
        source: AudioSource,
        elapsedOffset: TimeInterval
    ) throws -> [TranscriptSegment] {
        let output = try JSONDecoder().decode(WhisperOutput.self, from: data)
        return output.transcription.compactMap { segment in
            let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !isNonSpeechMarker(text) else { return nil }
            return TranscriptSegment(
                source: source,
                startElapsed: Double(segment.offsets.from) / 1000 + elapsedOffset,
                endElapsed: Double(segment.offsets.to) / 1000 + elapsedOffset,
                text: text)
        }
    }

    /// whisper marks silence/noise with a fully bracketed or parenthesized token
    /// (`[BLANK_AUDIO]`, `(silence)`). Those aren't speech, so drop them.
    private static func isNonSpeechMarker(_ text: String) -> Bool {
        (text.hasPrefix("[") && text.hasSuffix("]"))
            || (text.hasPrefix("(") && text.hasSuffix(")"))
    }

    // MARK: - Model & binary location

    static let modelFileName = "ggml-small.en.bin"

    static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Jot/Models", isDirectory: true)
    }

    /// Canonical on-disk location of the model (where setup downloads it).
    static var defaultModelURL: URL {
        modelsDirectory.appendingPathComponent(modelFileName)
    }

    /// Build a transcriber, resolving `whisper-cli` from the app bundle if
    /// present, otherwise from `PATH`. Jot ships as a brew install with
    /// `whisper-cpp` as a dependency (CONTEXT.md → External Dependencies), so in
    /// practice it's found on `PATH`. `nil` if no binary is available.
    static func makeDefault() -> WhisperCppTranscriber? {
        let binary = Bundle.main.url(forResource: "whisper-cli", withExtension: nil)
            ?? ExecutableLocator.locate("whisper-cli")
        guard let binary else { return nil }
        return WhisperCppTranscriber(modelURL: defaultModelURL, binaryURL: binary)
    }
}

/// Decodes the subset of whisper-cli's `-oj` JSON that we need. Offsets are in
/// milliseconds from the start of the chunk.
private struct WhisperOutput: Decodable {
    let transcription: [Segment]

    struct Segment: Decodable {
        let offsets: Offsets
        let text: String
    }

    struct Offsets: Decodable {
        let from: Int
        let to: Int
    }
}
