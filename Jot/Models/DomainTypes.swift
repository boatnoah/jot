import Foundation

/// Which stream a chunk / segment came from. Drives the speaker tag in the
/// transcript without any ML diarization (CONTEXT.md → Transcript).
enum AudioSource: String, Codable, Equatable {
    case microphone   // labeled "User"
    case system       // labeled "Others"

    var speakerTag: String {
        switch self {
        case .microphone: return "User"
        case .system: return "Others"
        }
    }
}

/// A single transcribed span, with timestamps already converted to
/// session-elapsed time (paused intervals excluded).
struct TranscriptSegment: Equatable {
    var source: AudioSource
    var startElapsed: TimeInterval
    var endElapsed: TimeInterval
    var text: String
}

/// Metadata persisted alongside the transcript and notes. Doubles as the live
/// session manifest written incrementally into the Recording Folder.
struct MeetingMetadata: Codable, Equatable {
    var sessionId: UUID
    var startedAt: Date
    var stoppedAt: Date?
    var elapsedSeconds: TimeInterval
    var whisperModel: String
    var agentUsed: String
    var generatedTitle: String?
}
