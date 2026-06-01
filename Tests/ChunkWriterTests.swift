import AVFoundation
import XCTest
@testable import Jot

/// Verifies the chunk-writing contract that the rest of the pipeline depends on:
/// arbitrary-rate input becomes 16 kHz mono WAV, chunks rotate with correct
/// elapsed offsets, and every chunk index produces both a mic and a system file
/// even when a source was silent.
final class ChunkWriterTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunkwriter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testConvertsTo16kMonoAndAlwaysWritesBothFiles() throws {
        let writer = ChunkWriter(directory: dir)
        var closed: [ClosedChunk] = []
        writer.onChunkClosed = { closed.append($0) }

        // 0.5s of 48 kHz mono audio to the mic only — system stays silent.
        try writer.append(sineBuffer(seconds: 0.5, sampleRate: 48_000), from: .microphone)
        writer.rotate(at: 30)
        try writer.append(sineBuffer(seconds: 0.25, sampleRate: 44_100), from: .microphone)
        writer.finish()

        XCTAssertEqual(closed.map(\.index), [0, 1])
        XCTAssertEqual(closed.map(\.elapsedOffset), [0, 30])

        // Both files exist for chunk 0, even though system was silent.
        let mic0 = try AVAudioFile(forReading: closed[0].micURL)
        let sys0 = try AVAudioFile(forReading: closed[0].systemURL)
        XCTAssertEqual(mic0.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(mic0.fileFormat.channelCount, 1)
        XCTAssertEqual(sys0.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(sys0.length, 0, "silent source should yield an empty (valid) WAV")

        // ~0.5s resampled to 16 kHz ≈ 8000 frames (allow tolerance for the resampler).
        XCTAssertEqual(Double(mic0.length), 8000, accuracy: 600)
    }

    func testFilesAreNamedByIndexAndSource() throws {
        let writer = ChunkWriter(directory: dir)
        writer.finish()  // closes chunk 0, creating both empty files
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("chunk-000-mic.wav").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("chunk-000-sys.wav").path))
    }

    // MARK: - Helpers

    /// A mono sine-wave buffer at the given sample rate, for feeding the writer.
    private func sineBuffer(seconds: Double, sampleRate: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frames = AVAudioFrameCount(seconds * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channel = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            channel[i] = 0.2 * Float(sin(2 * .pi * 440 * Double(i) / sampleRate))
        }
        return buffer
    }
}
