import AVFoundation

/// A finished chunk: both source files always exist (CONTEXT.md → Chunk), even
/// if one stream was silent for the window. `elapsedOffset` is the non-paused
/// session time that preceded this chunk, so whisper's chunk-relative timestamps
/// can be shifted to session-elapsed.
struct ClosedChunk: Equatable, Sendable {
    let index: Int
    let elapsedOffset: TimeInterval
    let micURL: URL
    let systemURL: URL
}

/// Writes captured audio into rotating 30-second chunk files, one pair (mic +
/// system) per chunk index. Incoming PCM at any rate/channel layout is converted
/// to **16 kHz mono** — whisper.cpp's required input. Whoever feeds this (the
/// recorder) must serialize calls onto a single queue; the writer is not
/// internally synchronized.
final class ChunkWriter {
    private let directory: URL

    /// 16 kHz mono signed-16-bit PCM WAV — what `whisper-cli` expects.
    private let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ]

    private(set) var currentIndex = 0
    private var chunkElapsedOffset: TimeInterval = 0
    private var files: [AudioSource: AVAudioFile] = [:]
    private var converters: [AudioSource: AVAudioConverter] = [:]

    /// Called when a chunk closes (rotation or finish) — the hook streaming
    /// transcription listens on.
    var onChunkClosed: ((ClosedChunk) -> Void)?

    init(directory: URL) {
        self.directory = directory
    }

    enum WriterError: Error {
        case converterUnavailable
        case bufferAllocationFailed
    }

    /// Append a buffer for one source to the current chunk, converting to the
    /// 16 kHz mono target. Lazily creates that source's file for this chunk.
    func append(_ buffer: AVAudioPCMBuffer, from source: AudioSource) throws {
        guard buffer.frameLength > 0 else { return }
        let file = try fileForCurrentChunk(source)
        let converted = try convert(buffer, to: file.processingFormat, source: source)
        if converted.frameLength > 0 {
            try file.write(from: converted)
        }
    }

    /// Close the current chunk (ensuring both files exist) and begin the next,
    /// whose offset is `elapsed` (non-paused session time so far).
    func rotate(at elapsed: TimeInterval) {
        closeCurrentChunk()
        currentIndex += 1
        chunkElapsedOffset = elapsed
    }

    /// Close the final chunk at end of session.
    func finish() {
        closeCurrentChunk()
    }

    // MARK: - Internals

    private func closeCurrentChunk() {
        // Guarantee both files exist even if a source never produced audio.
        for source in [AudioSource.microphone, .system] {
            _ = try? fileForCurrentChunk(source)
        }
        // Dropping the AVAudioFile references flushes and closes them.
        files.removeAll()
        converters.removeAll()
        onChunkClosed?(ClosedChunk(
            index: currentIndex,
            elapsedOffset: chunkElapsedOffset,
            micURL: url(for: .microphone, index: currentIndex),
            systemURL: url(for: .system, index: currentIndex)))
    }

    private func fileForCurrentChunk(_ source: AudioSource) throws -> AVAudioFile {
        if let file = files[source] { return file }
        let file = try AVAudioFile(
            forWriting: url(for: source, index: currentIndex),
            settings: outputSettings)
        files[source] = file
        return file
    }

    private func url(for source: AudioSource, index: Int) -> URL {
        let tag = source == .microphone ? "mic" : "sys"
        let name = String(format: "chunk-%03d-%@.wav", index, tag)
        return directory.appendingPathComponent(name)
    }

    /// Resample/convert one buffer to the file's processing format. The converter
    /// is cached per source so resampling stays continuous across appends.
    private func convert(
        _ input: AVAudioPCMBuffer,
        to outputFormat: AVAudioFormat,
        source: AudioSource
    ) throws -> AVAudioPCMBuffer {
        let converter: AVAudioConverter
        if let cached = converters[source], cached.inputFormat == input.format {
            converter = cached
        } else {
            guard let made = AVAudioConverter(from: input.format, to: outputFormat) else {
                throw WriterError.converterUnavailable
            }
            converters[source] = made
            converter = made
        }

        let ratio = outputFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw WriterError.bufferAllocationFailed
        }

        // The input block is invoked synchronously inside `convert`, so feeding
        // `input` is safe; box it to satisfy the @Sendable closure check.
        let boxedInput = UncheckedSendable(input)
        var providedInput = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, statusPointer in
            if providedInput {
                statusPointer.pointee = .noDataNow
                return nil
            }
            providedInput = true
            statusPointer.pointee = .haveData
            return boxedInput.value
        }
        if let conversionError { throw conversionError }
        return output
    }
}
