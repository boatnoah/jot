import AVFoundation

/// Coordinates the live capture streams into a session's chunk files. Every
/// capturer's buffers are funneled onto one serial queue (the `ChunkWriter` is
/// not internally synchronized), where they're written and metered. A timer
/// advances non-paused elapsed time and rotates chunks every 30s (CONTEXT.md →
/// Chunk, Elapsed Time).
///
/// `@unchecked Sendable`: all mutable state is confined to `queue`; callbacks are
/// `@Sendable` and delivered on the main queue.
final class AudioRecorder: @unchecked Sendable {
    private let capturers: [any AudioCapturing]
    private let writer: ChunkWriter
    private let chunkSeconds: TimeInterval
    private let queue = DispatchQueue(label: "com.jot.audio.recorder")
    private let tickInterval: TimeInterval = 0.1
    /// How long the mic may deliver nothing but exact-zero buffers before we
    /// flag it. A live mic always has a noise floor above `micSilenceEpsilon`,
    /// so sustained exact silence means a muted device or an ineffective grant
    /// (macOS hands back zero-filled buffers rather than erroring). Injectable
    /// so tests can drive it without waiting out the production window.
    private let micSilenceTimeout: TimeInterval
    private let micSilenceEpsilon = 1e-6

    private var timer: DispatchSourceTimer?
    private var elapsed: TimeInterval = 0
    private var nextRotation: TimeInterval
    private var running = false
    private var paused = false
    private var pendingPeaks: [AudioSource: Double] = [:]
    private var micSilentSeconds: TimeInterval = 0
    private var micSilenceWarned = false

    /// A chunk closed (rotation or stop) — the streaming-transcription hook.
    var onChunkClosed: (@Sendable (ClosedChunk) -> Void)?
    /// Combined level 0...1 (louder of the two streams), ~10 Hz, for the meter.
    var onLevel: (@Sendable (Double) -> Void)?
    /// Non-paused elapsed seconds, ~10 Hz.
    var onElapsed: (@Sendable (TimeInterval) -> Void)?
    /// Per-source peak since the last tick — diagnostics only.
    var onSourceLevel: (@Sendable (AudioSource, Double) -> Void)?
    /// Fires once per session if the mic is delivering buffers but they are all
    /// exact silence for `micSilenceTimeout` — the signature of a muted device
    /// or an ineffective mic grant. Without this, such a session records
    /// nothing while reporting success.
    var onMicSilent: (@Sendable () -> Void)?

    init(
        directory: URL,
        capturers: [any AudioCapturing],
        chunkSeconds: TimeInterval = 30,
        micSilenceTimeout: TimeInterval = 3
    ) {
        self.writer = ChunkWriter(directory: directory)
        self.capturers = capturers
        self.chunkSeconds = chunkSeconds
        self.nextRotation = chunkSeconds
        self.micSilenceTimeout = micSilenceTimeout
        writer.onChunkClosed = { [weak self] chunk in
            self?.deliverChunk(chunk)
        }
    }

    // MARK: - Lifecycle

    func start() async throws {
        for capturer in capturers {
            let source = capturer.source
            try await capturer.start { [weak self] buffer in
                // Copy synchronously — the capturer reuses its buffer after this
                // returns — then hand the copy to the serial queue.
                guard let self, let copy = buffer.deepCopy() else { return }
                let boxed = UncheckedSendable(copy)
                self.queue.async { self.handle(boxed.value, from: source) }
            }
        }
        queue.sync { self.beginTimer() }
    }

    func stop() {
        for capturer in capturers { capturer.stop() }
        queue.sync {
            running = false
            timer?.cancel()
            timer = nil
            writer.finish()
        }
    }

    func pause() { queue.async { self.paused = true } }
    func resume() { queue.async { self.paused = false } }

    // MARK: - Queue-confined work

    private func handle(_ buffer: AVAudioPCMBuffer, from source: AudioSource) {
        guard running, !paused else { return }
        pendingPeaks[source] = max(pendingPeaks[source] ?? 0, buffer.peakLevel)
        try? writer.append(buffer, from: source)
    }

    private func beginTimer() {
        running = true
        elapsed = 0
        nextRotation = chunkSeconds
        micSilentSeconds = 0
        micSilenceWarned = false
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + tickInterval, repeating: tickInterval)
        timer.setEventHandler { [weak self] in self?.tick() }
        self.timer = timer
        timer.resume()
    }

    private func tick() {
        guard running else { return }
        if !paused {
            elapsed += tickInterval
            if elapsed >= nextRotation {
                writer.rotate(at: nextRotation)
                nextRotation += chunkSeconds
            }
            let now = elapsed
            if let onElapsed { DispatchQueue.main.async { onElapsed(now) } }
            checkMicSilence()
        }
        // Combined level = louder stream since the last tick; reset for the next.
        let level = pendingPeaks.values.max() ?? 0
        if let onSourceLevel {
            let mic = pendingPeaks[.microphone] ?? 0
            let sys = pendingPeaks[.system] ?? 0
            DispatchQueue.main.async { onSourceLevel(.microphone, mic); onSourceLevel(.system, sys) }
        }
        pendingPeaks.removeAll(keepingCapacity: true)
        if let onLevel { DispatchQueue.main.async { onLevel(level) } }
    }

    /// Detect a mic that is "running but silent": buffers are arriving (the key
    /// is present this tick) yet every sample is exact zero. Only counts ticks
    /// where a mic buffer was actually seen, so it never false-fires when the
    /// engine simply isn't producing. Any real signal resets the streak. Fires
    /// `onMicSilent` once. Read `pendingPeaks` before `tick` clears it.
    private func checkMicSilence() {
        guard !micSilenceWarned, let micPeak = pendingPeaks[.microphone] else { return }
        guard micPeak <= micSilenceEpsilon else {
            micSilentSeconds = 0
            return
        }
        micSilentSeconds += tickInterval
        guard micSilentSeconds >= micSilenceTimeout else { return }
        micSilenceWarned = true
        NSLog("[AudioRecorder] microphone delivering only silence for %.0fs — muted device or ineffective mic grant?", micSilenceTimeout)
        if let onMicSilent { DispatchQueue.main.async { onMicSilent() } }
    }

    private func deliverChunk(_ chunk: ClosedChunk) {
        if let onChunkClosed { DispatchQueue.main.async { onChunkClosed(chunk) } }
    }
}
