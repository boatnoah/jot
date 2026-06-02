import Foundation

/// Owns a session's Recording Folder (CONTEXT.md → Recording Folder): the single
/// stable on-disk location for every artifact (chunk files, `metadata.json`,
/// `transcript.md`, `notes.md`). Created at Start with a datestamp-only name and
/// renamed to include the generated title once notes succeed. No temp directory
/// is used — this folder is the durable location for crash recovery and retry.
final class SessionStore {
    /// Current folder location; updated by `rename(toTitle:)`.
    private(set) var url: URL

    enum StoreError: Error, Equatable {
        case createFailed(String)
        case emptyTitle
    }

    /// Create `<notesDirectory>/YYYY-MM-DD HH-mm`. If that exact name is already
    /// taken (two sessions started in the same minute), a numeric suffix keeps it
    /// unique.
    init(notesDirectory: URL, startedAt: Date) throws {
        let stamp = Self.datestamp(startedAt)
        var candidate = notesDirectory.appendingPathComponent(stamp, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = notesDirectory.appendingPathComponent("\(stamp) (\(counter))", isDirectory: true)
            counter += 1
        }
        do {
            try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        } catch {
            throw StoreError.createFailed(error.localizedDescription)
        }
        self.url = candidate
    }

    // MARK: - Artifact paths

    var transcriptURL: URL { url.appendingPathComponent("transcript.md") }
    var notesURL: URL { url.appendingPathComponent("notes.md") }
    var metadataURL: URL { url.appendingPathComponent("metadata.json") }

    // MARK: - Writes

    func writeMetadata(_ metadata: MeetingMetadata) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: metadataURL, options: .atomic)
    }

    func writeTranscript(_ markdown: String) throws {
        try Data(markdown.utf8).write(to: transcriptURL, options: .atomic)
    }

    func writeNotes(_ markdown: String) throws {
        try Data(markdown.utf8).write(to: notesURL, options: .atomic)
    }

    /// Rename the folder to just `<Title>` (the date lives in `metadata.json`, not
    /// the folder name). Throws `.emptyTitle` if the title sanitizes to nothing,
    /// so the caller can simply keep the datestamp name. A numeric suffix keeps
    /// the name unique when another session already claimed the same title.
    func rename(toTitle rawTitle: String) throws {
        let title = Self.sanitizedTitle(rawTitle)
        guard !title.isEmpty else { throw StoreError.emptyTitle }
        let parent = url.deletingLastPathComponent()
        var destination = parent.appendingPathComponent(title, isDirectory: true)
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = parent.appendingPathComponent("\(title) (\(counter))", isDirectory: true)
            counter += 1
        }
        try FileManager.default.moveItem(at: url, to: destination)
        url = destination
    }

    // MARK: - Helpers

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH-mm"
        return f
    }()

    static func datestamp(_ date: Date) -> String { formatter.string(from: date) }

    /// Make an LLM-suggested title safe and tidy as a folder name: drop path
    /// separators and control whitespace, collapse runs of spaces, cap length.
    static func sanitizedTitle(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\n\r\t")
        let cleaned = raw.components(separatedBy: illegal).joined(separator: " ")
        let collapsed = cleaned.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let capped = collapsed.count > 60 ? String(collapsed.prefix(60)) : collapsed
        return capped.trimmingCharacters(in: .whitespaces)
    }
}
