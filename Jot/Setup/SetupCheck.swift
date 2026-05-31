import Foundation

/// One unit of first-run setup. The same abstraction backs two renderings: the
/// linear wizard (gate) and the later Setup / Diagnostics pane (checklist), per
/// CONTEXT.md → First-Run Setup.
///
/// A check owns both *how to verify itself* (`probe`) and *how to satisfy
/// itself* (`act`), so the view stays dumb and a diagnostics "Fix" button is
/// just `act()`. Conformers are `@Observable` classes; the views observe
/// `status` directly.
@MainActor
protocol SetupCheck: AnyObject, Identifiable {
    /// Identity and ordering within setup. `nonisolated` so `Identifiable.id`
    /// (used by SwiftUI `ForEach`) can read it without hopping to the main actor.
    nonisolated var step: SetupStep { get }

    /// Live state, derived from the world by `probe()` and updated by `act()`.
    var status: CheckStatus { get }

    // MARK: Presentation (wizard copy — friendly, one focus per screen)

    /// The big friendly question at the top of the step (not a label).
    var headline: String { get }

    /// Calm secondary copy under the headline.
    var body: String { get }

    /// Label for the yellow primary button while the step is unsatisfied. Once
    /// satisfied the wizard relabels it "Continue".
    var actionTitle: String { get }

    /// Optional dynamic supplementary line under the action (e.g. the chosen
    /// folder, the resolved Codex path, download progress in MB). `nil` hides it.
    var detail: String? { get }

    // MARK: Behavior

    /// Silently re-verify against the world and update `status`. Cheap and
    /// idempotent — run for every check on launch and on demand in diagnostics.
    func probe() async

    /// Perform the step's action (open a panel, request permission, download…)
    /// and update `status`. Triggered by the yellow button.
    func act() async
}

extension SetupCheck {
    nonisolated var id: SetupStep.ID { step.id }

    /// Most steps have no supplementary line.
    var detail: String? { nil }
}
