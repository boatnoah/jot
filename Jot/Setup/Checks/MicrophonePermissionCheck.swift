import AVFoundation
import AppKit

/// Step 2 — microphone permission, for capturing the `User` stream. Status is
/// always read live from the OS (never cached) so the diagnostics pane reflects
/// reality if the user later revokes it in System Settings.
@MainActor
@Observable
final class MicrophonePermissionCheck: SetupCheck {
    nonisolated let step = SetupStep.microphonePermission
    private(set) var status: CheckStatus = .unsatisfied

    let headline = "Can Jot hear you?"
    let body = "Jot records your microphone while a session is active — that's your half of the conversation."
    let actionTitle = "Allow microphone"

    func probe() async {
        status = Self.statusFor(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    func act() async {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            status = .running(nil)
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            status = granted ? .satisfied : Self.deniedStatus
        case .denied, .restricted:
            // Can't re-prompt once denied — send the user to System Settings.
            Self.openMicrophoneSettings()
            status = Self.deniedStatus
        case .authorized:
            status = .satisfied
        @unknown default:
            status = .unsatisfied
        }
    }

    private static func statusFor(_ auth: AVAuthorizationStatus) -> CheckStatus {
        switch auth {
        case .authorized: return .satisfied
        case .notDetermined: return .unsatisfied
        case .denied, .restricted: return deniedStatus
        @unknown default: return .unsatisfied
        }
    }

    private static let deniedStatus = CheckStatus.failed(
        "Microphone access is off. Turn it on for Jot in System Settings ▸ Privacy & Security ▸ Microphone."
    )

    private static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
