import Foundation

/// Step 5 — verify the notes agent can actually run and is authenticated, so a
/// broken or logged-out agent is caught at setup time rather than after the user
/// records a whole session (CONTEXT.md → First-Run Setup).
///
/// Backed by the real `NotesAgent.preflight()` (for Codex, `codex login
/// status`). Re-verified live on every launch — if the user later logs out, the
/// gate reopens to this step. No persisted "done" flag.
@MainActor
@Observable
final class CodexAuthCheck: SetupCheck {
    nonisolated let step = SetupStep.codexAuth
    private(set) var status: CheckStatus = .unsatisfied

    let headline = "Is Codex signed in?"
    let body = "Jot runs a quick check that Codex is installed and signed in so it can generate your notes."
    let actionTitle = "Check Codex"

    private(set) var detail: String?

    func probe() async {
        await verify()
    }

    func act() async {
        status = .running(nil)
        await verify()
    }

    private func verify() async {
        // Resolution shares the runtime registry, so this reflects exactly what
        // notes generation will use. nil means the executable wasn't found yet.
        guard let agent = NotesAgentKind.selected.makeAgent() else {
            detail = nil
            status = .failed("Couldn't find the Codex executable — finish the previous step first.")
            return
        }
        do {
            let result = try await agent.preflight()
            detail = result.detail
            if result.isReady {
                status = .satisfied
            } else {
                status = .failed(signInHint(result.detail))
            }
        } catch {
            detail = nil
            status = .failed(failureMessage(for: error))
        }
    }

    /// A not-ready preflight usually means logged out — nudge toward `codex
    /// login`, but keep any specific detail (e.g. a missing-node error).
    private func signInHint(_ detail: String) -> String {
        if detail.lowercased().contains("node") {
            return "\(detail)\n\nCodex needs Node.js on your PATH. Install it (e.g. via Homebrew) and try again."
        }
        return "Codex isn't signed in. Run `codex login` in your terminal, then check again."
    }

    private func failureMessage(for error: Error) -> String {
        guard let error = error as? NotesAgentError else {
            return "Couldn't verify Codex: \(error.localizedDescription)"
        }
        switch error {
        case .executableNotFound:
            return "Couldn't run Codex. Make sure Codex (and Node.js) are installed and on your PATH."
        case .notAuthenticated:
            return "Codex isn't signed in. Run `codex login` in your terminal, then check again."
        case .timedOut:
            return "Codex didn't respond in time. Check your connection and try again."
        default:
            return "Couldn't verify Codex. Try again, or reinstall Codex."
        }
    }
}
