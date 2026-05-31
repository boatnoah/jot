import AppKit

/// Step 1 — choose the folder where each session's transcript and notes are
/// saved (CONTEXT.md → Recording Folder). The app is unsandboxed, so we persist
/// a plain path rather than a security-scoped bookmark. Satisfied when a stored
/// path points at a writable directory.
@MainActor
@Observable
final class NotesDirectoryCheck: SetupCheck {
    nonisolated let step = SetupStep.notesDirectory
    private(set) var status: CheckStatus = .unsatisfied

    let headline = "Where should Jot keep your notes?"
    let body = "Each session saves a transcript and notes here. You can change it later."
    let actionTitle = "Choose folder…"

    var detail: String? { directory.map { "Saving to \($0.path)" } }

    private static let defaultsKey = "notesDirectoryPath"

    /// The chosen directory, if any. Read by the rest of the app once setup is
    /// complete.
    private(set) var directory: URL? {
        didSet { UserDefaults.standard.set(directory?.path, forKey: Self.defaultsKey) }
    }

    func probe() async {
        guard let path = UserDefaults.standard.string(forKey: Self.defaultsKey) else {
            status = .unsatisfied
            return
        }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if exists && isDir.boolValue && FileManager.default.isWritableFile(atPath: url.path) {
            directory = url
            status = .satisfied
        } else {
            status = .failed("That folder is missing or not writable. Pick another.")
        }
    }

    func act() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder for Jot's notes."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        directory = url
        status = FileManager.default.isWritableFile(atPath: url.path)
            ? .satisfied
            : .failed("Jot can't write to that folder. Pick another.")
    }
}
