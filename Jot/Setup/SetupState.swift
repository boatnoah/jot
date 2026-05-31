import Foundation
import Observation

/// Drives first-run setup: owns the ordered `SetupCheck`s, tracks which step the
/// wizard is showing, and derives completion. Mirrors the mock-driver pattern of
/// `AppState` — real probes where they're cheap, stubs where the subsystem isn't
/// built yet (Codex auth, test capture).
///
/// The wizard binds to `current` and the navigation methods; the later
/// diagnostics pane reads `checks` directly as a list. One model, two renderings
/// (CONTEXT.md → First-Run Setup).
@MainActor
@Observable
final class SetupState {
    /// All steps in canonical order.
    let checks: [any SetupCheck]

    /// Index of the step the wizard is currently showing. Distinct from "first
    /// unsatisfied" so the user can step back to revisit a satisfied step.
    private(set) var currentIndex: Int = 0

    init(checks: [any SetupCheck] = SetupState.makeDefaultChecks()) {
        precondition(!checks.isEmpty, "Setup needs at least one check")
        self.checks = checks
    }

    // MARK: - Derived state

    var current: any SetupCheck { checks[currentIndex] }

    /// Setup is the gate; recording stays disabled until every check passes.
    var isComplete: Bool { checks.allSatisfy { $0.status.isSatisfied } }

    /// 1-based position for the "step N of 7" whisper.
    var stepNumber: Int { currentIndex + 1 }
    var stepCount: Int { checks.count }

    /// The back chevron only appears when there's a prior step to revisit.
    var canGoBack: Bool { currentIndex > 0 }

    /// First step that isn't satisfied yet, or `nil` if all pass.
    var firstUnsatisfiedIndex: Int? {
        checks.firstIndex { !$0.status.isSatisfied }
    }

    // MARK: - Lifecycle

    /// Silently re-verify every check against the world, then land the wizard on
    /// the first incomplete step (the "resume where left off" behavior). Run on
    /// launch and whenever setup is reopened.
    func probeAll() async {
        for check in checks { await check.probe() }
        currentIndex = firstUnsatisfiedIndex ?? (checks.count - 1)
    }

    // MARK: - Navigation

    /// Run the current step's action (the yellow button while unsatisfied).
    func act() async {
        await current.act()
    }

    /// Advance from a satisfied current step to the next incomplete one. Jumps
    /// forward to wherever work remains (skipping already-satisfied steps, such
    /// as the auto-satisfied stubs). No-op if the current step isn't satisfied;
    /// if nothing remains, `isComplete` is now true and the view shows the
    /// completion screen.
    func advance() {
        guard current.status.isSatisfied else { return }
        if let next = firstUnsatisfiedIndex { currentIndex = next }
    }

    /// Step back to the previous (already-satisfied) step to revisit it.
    func back() {
        guard canGoBack else { return }
        currentIndex -= 1
    }

    // MARK: - Debug preview

    // NOTE: these stay outside any `#if DEBUG` block — the @Observable macro does
    // not instrument properties declared inside `#if`, so they wouldn't trigger
    // view updates. Only the menu item and preview bar that drive them are
    // gated to debug builds.

    /// When true, the wizard ignores its gate so every step (and the completion
    /// screen) can be paged through for design review, without granting
    /// permissions or downloading anything.
    private(set) var previewMode = false
    private(set) var previewShowCompletion = false

    func startPreview() {
        previewMode = true
        previewShowCompletion = false
        currentIndex = 0
    }

    func previewNext() {
        if currentIndex + 1 < checks.count {
            currentIndex += 1
        } else {
            previewShowCompletion = true
        }
    }

    func previewBack() {
        if previewShowCompletion {
            previewShowCompletion = false
        } else if currentIndex > 0 {
            currentIndex -= 1
        }
    }

    func endPreview() {
        previewMode = false
        previewShowCompletion = false
    }

    // MARK: - Default composition

    /// The seven setup checks in spec order. Codex-auth and test-capture are
    /// stubbed behind the protocol until the real pipeline lands.
    static func makeDefaultChecks() -> [any SetupCheck] {
        [
            NotesDirectoryCheck(),
            MicrophonePermissionCheck(),
            ScreenRecordingPermissionCheck(),
            CodexExecutableCheck(),
            CodexAuthCheck(),
            WhisperModelCheck(),
            TestCaptureCheck(),
        ]
    }
}
