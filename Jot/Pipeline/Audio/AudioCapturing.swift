import AVFoundation

/// A single live audio stream (mic or system). Implementations deliver PCM
/// buffers via the callback on their own (real-time) thread; the buffer is only
/// valid for the duration of the call, so the recorder copies it before handing
/// it off (`AVAudioPCMBuffer.copy()` below).
protocol AudioCapturing: AnyObject, Sendable {
    var source: AudioSource { get }
    /// Begin capturing. `onBuffer` may be called on a real-time audio thread.
    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws
    func stop()
}

enum AudioCaptureError: Error {
    case micUnavailable
    case systemAudioUnavailable(String)
    case formatUnavailable
}

/// Hands a non-Sendable value across a concurrency boundary. Safe here because
/// ownership is transferred — the producer doesn't touch it after passing it on.
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

extension AVAudioPCMBuffer {
    /// Deep copy of the valid frames. Tap buffers are reused by the engine after
    /// the callback returns, so we must copy before any async hand-off.
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }
        copy.frameLength = frameLength
        let channels = Int(format.channelCount)
        let frames = Int(frameLength)
        if let src = floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<channels { dst[ch].update(from: src[ch], count: frames) }
        } else if let src = int16ChannelData, let dst = copy.int16ChannelData {
            for ch in 0..<channels { dst[ch].update(from: src[ch], count: frames) }
        } else if let src = int32ChannelData, let dst = copy.int32ChannelData {
            for ch in 0..<channels { dst[ch].update(from: src[ch], count: frames) }
        } else {
            return nil
        }
        return copy
    }

    /// Peak amplitude (0...1) of the buffer's first channel — drives the level
    /// meter. Float formats only; returns 0 otherwise.
    var peakLevel: Double {
        guard let data = floatChannelData, frameLength > 0 else { return 0 }
        let samples = data[0]
        var peak: Float = 0
        for i in 0..<Int(frameLength) { peak = max(peak, abs(samples[i])) }
        return Double(min(peak, 1))
    }
}
