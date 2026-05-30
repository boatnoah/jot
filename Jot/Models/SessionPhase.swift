import Foundation

/// The primary state machine for a capture session. Exactly one session may be
/// active or processing at a time (see CONTEXT.md → Session).
enum SessionPhase: Equatable {
    case idle
    case recording
    case paused
    case processing(ProcessingStage)
    case complete
    case failed(FailureKind)

    /// Coarse status used to drive UI tint across both the menu bar icon and the
    /// Jot Dot. Keeps SessionPhase free of any UI-framework dependency.
    var status: StatusKind {
        switch self {
        case .idle: return .idle
        case .recording: return .active
        case .paused: return .paused
        case .processing: return .processing
        case .complete: return .success
        case .failed: return .failure
        }
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }

    var isProcessing: Bool {
        if case .processing = self { return true }
        return false
    }
}

/// The ordered stages the pipeline moves through after Stop. Because chunks are
/// transcribed during recording (streaming transcription), `transcribing` is
/// usually just a brief wait on the final chunk.
enum ProcessingStage: Equatable, CaseIterable {
    case finalizingAudio
    case transcribing
    case savingTranscript
    case generatingNotes

    var label: String {
        switch self {
        case .finalizingAudio: return "Finalizing audio"
        case .transcribing: return "Transcribing"
        case .savingTranscript: return "Saving transcript"
        case .generatingNotes: return "Generating notes"
        }
    }
}

/// The three real failure modes plus the terminal "too large" variant. The
/// transcript is the durable guarantee, so `notes` and `transcriptTooLarge`
/// never lose the transcript.
enum FailureKind: Equatable {
    case recording
    case transcription
    case notes
    case transcriptTooLarge

    var title: String {
        switch self {
        case .recording: return "Recording failed"
        case .transcription: return "Transcription failed"
        case .notes: return "Notes failed"
        case .transcriptTooLarge: return "Transcript too large"
        }
    }

    var detail: String? {
        switch self {
        case .recording: return "The session could not be recorded."
        case .transcription: return "Audio was kept. You can retry transcription."
        case .notes: return "Transcript saved. You can retry notes."
        case .transcriptTooLarge: return "Transcript saved, but it was too large for Codex notes generation."
        }
    }

    /// Whether this failure offers a retry action at all.
    var isRetryable: Bool {
        switch self {
        case .transcription, .notes: return true
        case .recording, .transcriptTooLarge: return false
        }
    }
}

/// UI-agnostic status category. Mapped to Color in the SwiftUI layer and to
/// NSColor in the AppKit menu-bar layer.
enum StatusKind {
    case idle
    case active
    case paused
    case processing
    case success
    case failure
}
