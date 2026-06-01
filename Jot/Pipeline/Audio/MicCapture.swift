import AVFoundation

/// Captures the microphone (the `User` stream) via `AVAudioEngine`. Taps the
/// input node and forwards each buffer; the engine owns the buffer, so the
/// consumer must copy it before any async use.
final class MicCapture: AudioCapturing, @unchecked Sendable {
    let source = AudioSource.microphone
    private let engine = AVAudioEngine()

    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        // Ensure the mic is actually authorized for *this* process. Without an
        // effective grant, macOS hands AVAudioEngine zero-filled buffers (silent
        // audio of the right length) rather than an error.
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                throw AudioCaptureError.micUnavailable
            }
        default:
            throw AudioCaptureError.micUnavailable
        }

        let input = engine.inputNode
        // The actual hardware input format. On macOS this is the reliable format
        // to tap with; `outputFormat(forBus:)` can report a stale/default layout
        // that yields a -10877 (kAudioUnitErr_InvalidElement) and silent buffers.
        // The ChunkWriter resamples to 16 kHz mono downstream.
        let inFormat = input.inputFormat(forBus: 0)
        let format = inFormat.sampleRate > 0 ? inFormat : input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioCaptureError.micUnavailable
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            onBuffer(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
            NSLog("[MicCapture] started: %.0f Hz, %u ch", format.sampleRate, format.channelCount)
        } catch {
            NSLog("[MicCapture] engine.start() failed: %@", error.localizedDescription)
            input.removeTap(onBus: 0)
            throw AudioCaptureError.micUnavailable
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
