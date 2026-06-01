import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Captures system audio (the `Others` stream) via ScreenCaptureKit, which is
/// the only way to tap output audio on macOS and is why Jot needs Screen
/// Recording permission (CONTEXT.md → System Audio Permission). Video is
/// configured minimally and ignored — we only consume the audio output. Jot's
/// own audio is excluded so interaction sounds don't bleed into the recording.
final class SystemAudioCapture: NSObject, AudioCapturing, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    let source = AudioSource.system

    private let queue = DispatchQueue(label: "com.jot.audio.system")
    private var stream: SCStream?
    private var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {
        self.onBuffer = onBuffer

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            throw AudioCaptureError.systemAudioUnavailable(error.localizedDescription)
        }
        guard let display = content.displays.first else {
            throw AudioCaptureError.systemAudioUnavailable("No display available to attach the audio stream to.")
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // We don't use video; keep it tiny so it costs almost nothing.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            try await stream.startCapture()
        } catch {
            throw AudioCaptureError.systemAudioUnavailable(error.localizedDescription)
        }
        self.stream = stream
    }

    func stop() {
        stream?.stopCapture { _ in }
        stream = nil
        onBuffer = nil
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let pcm = Self.pcmBuffer(from: sampleBuffer) else { return }
        onBuffer?(pcm)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // The stream stopped unexpectedly (e.g. permission revoked). The session
        // controller will surface this when it owns the recorder.
        NSLog("SystemAudioCapture stopped: \(error.localizedDescription)")
    }

    // MARK: - CMSampleBuffer → AVAudioPCMBuffer

    /// Build an owned PCM buffer from a ScreenCaptureKit audio sample buffer.
    private static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee
        else { return nil }

        var streamDescription = asbd
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else { return nil }

        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList)
        guard status == noErr else { return nil }
        return buffer
    }
}
