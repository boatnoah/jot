import Foundation

/// Result of an agent preflight check (executable found, authenticated, etc.).
struct AgentStatus: Equatable {
    var isReady: Bool
    var detail: String
}

/// Generates notes from a finished transcript by invoking a local CLI
/// non-interactively. The only v1 implementation is `CodexAgent`; `ClaudeAgent`
/// is intentionally left room for.
protocol NotesAgent: Sendable {
    var displayName: String { get }
    func preflight() async throws -> AgentStatus
    func generateNotes(transcriptURL: URL, metadata: MeetingMetadata) async throws -> String
}

enum NotesAgentError: Error {
    case executableNotFound
    case notAuthenticated
    case timedOut
    case transcriptTooLarge
    case notImplemented
}

/// Invokes the user's authenticated `codex` CLI via `Process` with explicit
/// arguments, stdin/stdout pipes, and a timeout. Never shell-interpolates
/// transcript or prompt text. Stubbed for now.
struct CodexAgent: NotesAgent {
    var displayName: String { "Codex" }

    /// Overridable executable path; default resolved from PATH during setup.
    var executableURL: URL

    /// Hardcoded for now; will become configurable (CONTEXT.md → 5-min default).
    var timeout: Duration = .seconds(300)

    func preflight() async throws -> AgentStatus {
        throw NotesAgentError.notImplemented
    }

    func generateNotes(transcriptURL: URL, metadata: MeetingMetadata) async throws -> String {
        throw NotesAgentError.notImplemented
    }
}
