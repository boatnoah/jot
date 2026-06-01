import Foundation

/// Finds a CLI executable by name. Searches `PATH` plus the common install
/// locations a GUI process often doesn't inherit (Homebrew, npm-global,
/// ~/.local/bin), and honors an explicit override path. Shared by setup's agent
/// detection and the runtime notes-agent registry so there's one definition of
/// "where do we look".
enum ExecutableLocator {
    /// First runnable match for `name`: the explicit override (if runnable),
    /// otherwise the first hit across the search directories.
    static func locate(_ name: String, explicitPath: String? = nil) -> URL? {
        if let explicitPath, isRunnable(explicitPath) {
            return URL(fileURLWithPath: explicitPath)
        }
        for dir in searchDirectories() {
            let candidate = dir + "/" + name
            if isRunnable(candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    static func isRunnable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    /// The current environment with `PATH` widened to include the search
    /// directories. Essential for CLIs that are themselves scripts: e.g. `codex`
    /// is `#!/usr/bin/env node`, so it needs `node` on `PATH`. A GUI app launched
    /// from Finder inherits the minimal launchd `PATH` (`/usr/bin:/bin`), which
    /// omits Homebrew — so without this, a node-based agent fails to start.
    static func augmentedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        let path = (searchDirectories() + existing).filter { seen.insert($0).inserted }
        env["PATH"] = path.joined(separator: ":")
        return env
    }

    /// `PATH` directories first, then common locations the GUI environment may
    /// not include, de-duplicated in order.
    static func searchDirectories() -> [String] {
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
