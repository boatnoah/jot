import AVFoundation
import XCTest
@testable import Jot

/// Verifies the "running but silent" mic guard: a mic that delivers buffers
/// which are all exact zero (a muted device or an ineffective grant) trips
/// `onMicSilent`, while a mic with real signal never does. The timeout is
/// injected tiny so the test doesn't wait out the production window.
final class AudioRecorderTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audiorecorder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testWarnsWhenMicDeliversOnlySilence() async throws {
        let recorder = AudioRecorder(
            directory: dir,
            capturers: [FakeCapture(source: .microphone, sampleValue: 0)],
            micSilenceTimeout: 0.3)

        let warned = expectation(description: "onMicSilent fires")
        let boxed = UncheckedSendable(warned)
        recorder.onMicSilent = { boxed.value.fulfill() }

        try await recorder.start()
        await fulfillment(of: [warned], timeout: 2)
        recorder.stop()
    }

    func testDoesNotWarnWhenMicHasSignal() async throws {
        let recorder = AudioRecorder(
            directory: dir,
            capturers: [FakeCapture(source: .microphone, sampleValue: 0.5)],
            micSilenceTimeout: 0.3)

        let notWarned = expectation(description: "onMicSilent does not fire")
        notWarned.isInverted = true
        let boxed = UncheckedSendable(notWarned)
        recorder.onMicSilent = { boxed.value.fulfill() }

        try await recorder.start()
        await fulfillment(of: [notWarned], timeout: 1)
        recorder.stop()
    }
}

/// A fake `AudioCapturing` that emits a steady stream of 48 kHz mono float
/// buffers filled with a constant sample, so its per-buffer peak is exactly
/// `sampleValue` — 0 to simulate a muted/zero-filled mic, non-zero for signal.
private final class FakeCapture: AudioCapturing, @unchecked Sendable {
    let source: AudioSource
    private let sampleValue: Float
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
    private let queue = DispatchQueue(label: "test.fakecapture")
    private var timer: DispatchSourceTimer?

    init(source: AudioSource, sampleValue: Float) {
        self.source = source
        self.sampleValue = sampleValue
    }

    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Faster than the recorder's 0.1s tick so every tick sees a buffer.
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))
        timer.setEventHandler { [self] in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 960) else { return }
            buffer.frameLength = 960
            let channel = buffer.floatChannelData![0]
            for i in 0..<Int(buffer.frameLength) { channel[i] = sampleValue }
            onBuffer(buffer)
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}
