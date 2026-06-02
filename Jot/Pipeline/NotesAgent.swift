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
    /// A short title for the session, used to rename the Recording Folder. Has a
    /// default (local derive from the notes) so this stays agent-agnostic — no
    /// agent is forced to implement it, and any agent *may* override with a
    /// smarter dedicated call. See the extension below.
    func generateTitle(fromNotes notes: String, metadata: MeetingMetadata) async throws -> String
}

extension NotesAgent {
    /// Default title: derive it locally from the generated notes, so every agent
    /// works out of the box without a bespoke call. Throws if nothing usable is
    /// found, which the caller treats as non-fatal (folder keeps its datestamp
    /// name — CONTEXT.md → Recording Folder).
    func generateTitle(fromNotes notes: String, metadata: MeetingMetadata) async throws -> String {
        guard let title = NotesTitle.derive(fromNotes: notes) else {
            throw NotesAgentError.generationFailed("No title could be derived from the notes.")
        }
        return title
    }
}

/// Agent-agnostic local title derivation: the default backing for
/// `NotesAgent.generateTitle`. Prefers the first sentence of the notes' Summary
/// section, falling back to the first real content line; strips Markdown and
/// caps the length to a tidy, folder-friendly phrase.
enum NotesTitle {
    static func derive(fromNotes notes: String) -> String? {
        let lines = notes.components(separatedBy: .newlines)
        if let summary = summaryParagraph(in: lines),
           let sentence = firstSentence(of: summary) {
            let title = tidy(sentence)
            if isUsable(title) { return title }
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let title = tidy(trimmed)
            if isUsable(title) { return title }
        }
        return nil
    }

    /// The body of the `## Summary` section as a single string (its lines joined),
    /// or nil if there's no Summary heading or it's empty.
    private static func summaryParagraph(in lines: [String]) -> String? {
        guard let start = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("## summary")
        }) else { return nil }
        var body: [String] = []
        for line in lines[(start + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { break }            // next section
            if trimmed.isEmpty { if body.isEmpty { continue } else { break } }
            body.append(trimmed)
        }
        let joined = body.joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }

    private static func firstSentence(of text: String) -> String? {
        if let range = text.range(of: ". ") {
            return String(text[..<range.lowerBound])
        }
        return text.hasSuffix(".") ? String(text.dropLast()) : text
    }

    /// Reduce arbitrary agent output to a single clean word suitable for a folder
    /// name: take the first token of the first non-empty line and keep only its
    /// letters/digits (dropping quotes, markdown, trailing punctuation), then
    /// capitalize it. `nil` if nothing usable remains. Used by agents that
    /// generate the title with a dedicated one-word call.
    static func singleWord(from raw: String) -> String? {
        let firstLine = raw
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""
        guard let token = firstLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).first else {
            return nil
        }
        let cleaned = String(token.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        guard !cleaned.isEmpty, isUsable(cleaned) else { return nil }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    /// A derived title is only usable if it has content and isn't the agent's
    /// way of saying "nothing here" (e.g. a Summary section that reads "None").
    private static func isUsable(_ title: String) -> Bool {
        !title.isEmpty && title.lowercased() != "none"
    }

    /// Strip Markdown emphasis/markers, collapse whitespace, cap to 8 words.
    private static func tidy(_ raw: String) -> String {
        let stripped = raw.filter { !"*_`#>".contains($0) }
        let words = stripped.split(whereSeparator: { $0 == " " || $0.isNewline })
        return words.prefix(8).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
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
