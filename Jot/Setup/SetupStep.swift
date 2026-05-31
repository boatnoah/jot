import Foundation

/// Identity and canonical ordering of the first-run setup steps (CONTEXT.md →
/// First-Run Setup). The wizard walks these in `allCases` order as a gate; the
/// later Setup / Diagnostics pane renders the same set as a checklist. Display
/// copy lives on the individual `SetupCheck`, not here — this is pure identity.
enum SetupStep: Int, CaseIterable, Identifiable, Equatable {
    case notesDirectory
    case microphonePermission
    case screenRecordingPermission
    case codexExecutable
    case codexAuth
    case whisperModel
    case testCapture

    var id: Int { rawValue }

    /// Short name for the diagnostics checklist (the wizard uses the headline
    /// instead). Kept terse — the wizard's friendly question carries the tone.
    var shortTitle: String {
        switch self {
        case .notesDirectory: return "Notes folder"
        case .microphonePermission: return "Microphone"
        case .screenRecordingPermission: return "System audio"
        case .codexExecutable: return "Find Codex"
        case .codexAuth: return "Codex sign-in"
        case .whisperModel: return "Speech model"
        case .testCapture: return "Quick test"
        }
    }
}
