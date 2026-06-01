import Foundation

/// Step 4 — locate the `codex` executable used by the Notes Agent (CONTEXT.md →
/// Notes Agent). Delegates lookup to the shared `ExecutableLocator` (same search
/// the runtime `NotesAgentKind` registry uses) and honors a manual override.
/// Satisfied when a runnable `codex` is found.
@MainActor
@Observable
final class CodexExecutableCheck: SetupCheck {
    nonisolated let step = SetupStep.codexExecutable
    private(set) var status: CheckStatus = .unsatisfied

    let headline = "Find Codex on your Mac"
    let body = "Jot uses the Codex command-line tool to turn transcripts into notes."
    let actionTitle = "Detect Codex"

    var detail: String? { resolvedURL.map { "Found at \($0.path)" } }

    /// The agent being detected. Drives the lookup and the override key so this
    /// stays in lockstep with the runtime registry.
    private let kind = NotesAgentKind.codex

    /// Resolved executable, once found.
    private(set) var resolvedURL: URL?

    func probe() async {
        resolvedURL = kind.locateExecutable()
        status = resolvedURL != nil
            ? .satisfied
            : .failed("Couldn't find Codex. Install it, or point Jot at it manually.")
    }

    func act() async {
        await probe()
    }

    /// Let the user supply an explicit path when auto-detection fails (wired to
    /// a text field in the view). Persists and re-probes.
    func setManualPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: kind.executablePathDefaultsKey)
        resolvedURL = ExecutableLocator.isRunnable(path) ? URL(fileURLWithPath: path) : nil
        status = resolvedURL != nil
            ? .satisfied
            : .failed("That path isn't a runnable executable.")
    }
}
