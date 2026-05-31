import AppKit

/// Relaunches the app: spawns a detached shell that waits for this process to
/// exit, then reopens the bundle. Used after granting Screen Recording, which
/// macOS only applies to a fresh process (CONTEXT.md → System Audio Permission).
/// Relies on the app being unsandboxed (`ENABLE_APP_SANDBOX: NO`).
@MainActor
enum AppRelaunch {
    static func now() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; open \"\(path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }
}
