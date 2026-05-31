import Foundation

/// The live state of a single `SetupCheck`. A check derives this from the world
/// on `probe()` (so "resume where left off" and the diagnostics pane both read
/// real truth), and updates it as `act()` runs.
enum CheckStatus: Equatable {
    /// Not done yet — fresh, or the user hasn't acted. The wizard parks here.
    case unsatisfied

    /// In progress. The optional fraction (0...1) drives the model-download
    /// progress fill; `nil` means indeterminate (e.g. waiting on an OS dialog).
    case running(Double?)

    /// Requirement met. The wizard's button becomes "Continue".
    case satisfied

    /// Probed and actively broken (auth expired, model went missing). Carries a
    /// human-readable reason for the screen copy. Eraser-red in the UI.
    case failed(String)

    var isSatisfied: Bool {
        if case .satisfied = self { return true }
        return false
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }
}
