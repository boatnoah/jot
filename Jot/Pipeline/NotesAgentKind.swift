import Foundation

/// The set of notes agents Jot can use, and the factory that builds a configured
/// `NotesAgent` for each. v1 ships only Codex; adding Claude Code or Cursor is a
/// new case here plus a ~30-line adapter (they share `ProcessRunner` and the
/// same `NotesPrompt`). The user's choice is persisted and surfaced in setup.
enum NotesAgentKind: String, CaseIterable, Identifiable {
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: return "Codex"
        }
    }

    /// The CLI command each agent is invoked as — also what setup looks for.
    var commandName: String {
        switch self {
        case .codex: return "codex"
        }
    }

    /// UserDefaults key for a manual override path to this agent's executable.
    var executablePathDefaultsKey: String {
        "\(rawValue)ExecutablePathOverride"
    }

    /// Resolve the executable (override path, then PATH/common dirs).
    func locateExecutable() -> URL? {
        let override = UserDefaults.standard.string(forKey: executablePathDefaultsKey)
        return ExecutableLocator.locate(commandName, explicitPath: override)
    }

    /// Build a ready-to-use agent, or `nil` if its executable can't be found.
    func makeAgent() -> (any NotesAgent)? {
        guard let executableURL = locateExecutable() else { return nil }
        switch self {
        case .codex:
            return CodexAgent(executableURL: executableURL)
        }
    }

    // MARK: - Selection

    private static let selectionKey = "selectedNotesAgent"

    /// The user's chosen agent (defaults to Codex).
    static var selected: NotesAgentKind {
        get {
            UserDefaults.standard.string(forKey: selectionKey)
                .flatMap(NotesAgentKind.init(rawValue:)) ?? .codex
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: selectionKey) }
    }

    /// Build the currently selected agent.
    static func makeSelectedAgent() -> (any NotesAgent)? {
        selected.makeAgent()
    }
}
