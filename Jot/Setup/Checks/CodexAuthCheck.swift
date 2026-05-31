import Foundation

/// Step 5 — verify Codex is signed in and can actually answer, by running a
/// tiny non-interactive self-test (CONTEXT.md → First-Run Setup).
///
/// STUB: the real `NotesAgent` / `CodexAgent` pipeline isn't built yet, so this
/// check is a placeholder behind the `SetupCheck` protocol. When `CodexAgent`
/// lands, only this file changes — `probe()`/`act()` will invoke `codex` with a
/// throwaway prompt and confirm a non-error response. For now it auto-satisfies
/// so the wizard is fully walkable end to end.
@MainActor
@Observable
final class CodexAuthCheck: SetupCheck {
    nonisolated let step = SetupStep.codexAuth
    private(set) var status: CheckStatus = .unsatisfied

    let headline = "Is Codex signed in?"
    let body = "Jot runs a quick test to make sure Codex can generate notes for you."
    let actionTitle = "Run sign-in test"

    // Until the real self-test exists, remember that the user ran the stub so a
    // completed setup stays complete across launches (rather than reappearing).
    private static let doneKey = "codexAuthStubCompleted"

    func probe() async {
        // TODO(pipeline): run a real `codex` self-test once CodexAgent exists.
        status = UserDefaults.standard.bool(forKey: Self.doneKey) ? .satisfied : .unsatisfied
    }

    func act() async {
        status = .running(nil)
        // TODO(pipeline): real self-test. Simulate a brief check for now.
        try? await Task.sleep(for: .milliseconds(400))
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        status = .satisfied
    }
}
