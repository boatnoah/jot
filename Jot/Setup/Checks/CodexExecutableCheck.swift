import Foundation

/// Step 4 — locate the `codex` executable used by the Notes Agent (CONTEXT.md →
/// Notes Agent). Searches `PATH` plus common install locations, and honors a
/// manual override the user can set if auto-detection misses it. Satisfied when
/// a runnable `codex` is found.
@MainActor
@Observable
final class CodexExecutableCheck: SetupCheck {
    nonisolated let step = SetupStep.codexExecutable
    private(set) var status: CheckStatus = .unsatisfied

    let headline = "Find Codex on your Mac"
    let body = "Jot uses the Codex command-line tool to turn transcripts into notes."
    let actionTitle = "Detect Codex"

    var detail: String? { resolvedPath.map { "Found at \($0)" } }

    private static let overrideKey = "codexExecutablePathOverride"

    /// Resolved path to the executable, once found. Read by `CodexAgent` later.
    private(set) var resolvedPath: String?

    func probe() async {
        resolvedPath = locate()
        status = resolvedPath != nil
            ? .satisfied
            : .failed("Couldn't find Codex. Install it, or point Jot at it manually.")
    }

    func act() async {
        await probe()
    }

    /// Let the user supply an explicit path when auto-detection fails (wired to
    /// a text field in the view). Persists and re-probes.
    func setManualPath(_ path: String) {
        UserDefaults.standard.set(path, forKey: Self.overrideKey)
        resolvedPath = isRunnable(path) ? path : nil
        status = resolvedPath != nil
            ? .satisfied
            : .failed("That path isn't a runnable executable.")
    }

    // MARK: - Lookup

    private func locate() -> String? {
        if let override = UserDefaults.standard.string(forKey: Self.overrideKey),
           isRunnable(override) {
            return override
        }
        for dir in Self.searchDirectories() where isRunnable(dir + "/codex") {
            return dir + "/codex"
        }
        return nil
    }

    private func isRunnable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    /// `PATH` directories first, then common install locations the GUI process
    /// may not inherit (Homebrew, npm-global, ~/.local/bin).
    private static func searchDirectories() -> [String] {
        var dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let home = NSHomeDirectory()
        dirs += [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "\(home)/.local/bin",
            "\(home)/.npm-global/bin",
        ]
        var seen = Set<String>()
        return dirs.filter { seen.insert($0).inserted }
    }
}
