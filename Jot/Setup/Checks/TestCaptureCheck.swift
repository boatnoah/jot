import Foundation

/// Step 7 — an optional short test capture that proves the full audio path works
/// before the user relies on it (CONTEXT.md → First-Run Setup).
///
/// STUB: depends on the real audio capture + transcription pipeline, which isn't
/// built yet. Placeholder behind the `SetupCheck` protocol; auto-satisfies so
/// the gate can complete. Because the step is *optional*, even the real version
/// will let the user skip it — `act()` will run a few seconds of capture and
/// show the level meter, but satisfaction shouldn't strictly require success.
@MainActor
@Observable
final class TestCaptureCheck: SetupCheck {
    nonisolated let step = SetupStep.testCapture
    private(set) var status: CheckStatus = .unsatisfied

    let headline = "Make a quick test recording?"
    let body = "Optional: record a few seconds to confirm Jot hears both you and your Mac."
    let actionTitle = "Record a test"

    // Optional step. Until the real capture path exists, remember completion so
    // a finished setup stays finished across launches.
    private static let doneKey = "testCaptureStubCompleted"

    func probe() async {
        status = UserDefaults.standard.bool(forKey: Self.doneKey) ? .satisfied : .unsatisfied
    }

    func act() async {
        status = .running(nil)
        // TODO(pipeline): run a real short capture through the audio path.
        try? await Task.sleep(for: .milliseconds(600))
        UserDefaults.standard.set(true, forKey: Self.doneKey)
        status = .satisfied
    }
}
