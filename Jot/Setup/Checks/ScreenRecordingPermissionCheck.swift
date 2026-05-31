import AppKit
import CoreGraphics

/// Step 3 — Screen Recording permission, which ScreenCaptureKit requires to
/// capture system audio (the `Others` stream). This is the trust moment: the
/// copy must reassure that Jot does not record the screen (CONTEXT.md →
/// System Audio Permission).
@MainActor
@Observable
final class ScreenRecordingPermissionCheck: SetupCheck {
    nonisolated let step = SetupStep.screenRecordingPermission
    private(set) var status: CheckStatus = .unsatisfied

    let headline = "Let Jot capture the other side"
    let body = "To record what others say, Jot needs Screen Recording permission. Jot does not record your screen — only system audio."
    let actionTitle = "Allow system audio"

    func probe() async {
        // Preflight reports current grant without prompting.
        status = CGPreflightScreenCaptureAccess()
            ? .satisfied
            : .unsatisfied
    }

    func act() async {
        if CGPreflightScreenCaptureAccess() {
            status = .satisfied
            return
        }
        // First call shows the system prompt and returns immediately; the grant
        // doesn't take effect until relaunch, so guide the user explicitly.
        status = .running(nil)
        let granted = CGRequestScreenCaptureAccess()
        if granted {
            status = .satisfied
        } else {
            Self.openScreenRecordingSettings()
            status = .failed(
                "Turn on Screen Recording for Jot in System Settings ▸ Privacy & Security, then relaunch Jot."
            )
        }
    }

    private static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
