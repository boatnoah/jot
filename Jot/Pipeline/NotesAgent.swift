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

enum NotesAgentError: Error, Equatable {
    case executableNotFound
    case notAuthenticated
    case timedOut
    case transcriptTooLarge
    /// The agent ran but returned no usable notes (empty output, non-zero exit).
    case generationFailed(String)
    case notImplemented
}
