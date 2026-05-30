import Foundation
import Observation

/// Observable session state plus a mock driver that walks the state machine
/// without any real audio/transcription/notes work. This lets the Jot Dot be
/// fully interactive while the real pipeline is built behind the same surface.
@MainActor
@Observable
final class AppState {
    private(set) var phase: SessionPhase = .idle

    /// Session-elapsed time in seconds (paused time excluded).
    private(set) var elapsed: TimeInterval = 0

    /// Rolling buffer of recent audio levels (0...1) for the single combined
    /// level meter. Newest sample last.
    private(set) var levels: [Double] = Array(repeating: 0, count: meterSampleCount)

    /// Processing progress 0...1 for the current stage.
    private(set) var progress: Double = 0

    /// When true, the Dot forces itself expanded regardless of hover — used for
    /// brief "look at me" moments (recording just started, notes just ready).
    /// Otherwise expansion is purely hover-driven by the view.
    private(set) var announce: Bool = false

    /// Title that Codex would generate; mocked on Complete.
    private(set) var generatedTitle: String?

    static let meterSampleCount = 18

    private var ticker: Task<Void, Never>?
    private var pipeline: Task<Void, Never>?
    private var announceTask: Task<Void, Never>?

    // MARK: - User actions

    func start() {
        cancelWork()
        elapsed = 0
        progress = 0
        generatedTitle = nil
        phase = .recording
        // Plays before capture would begin, so it never bleeds into the recording.
        SoundPlayer.shared.play(.doublePop)
        startTicking()
        // Briefly force-expand so the user confirms capture is live, then it
        // returns to hover-driven behavior.
        announceBriefly()
    }

    func pause() {
        guard phase.isRecording else { return }
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .recording
    }

    func stop() {
        guard phase.isRecording || phase == .paused else { return }
        ticker?.cancel()
        // Plays after capture has stopped — the "now working on it" cue.
        SoundPlayer.shared.play(.keyTap)
        runMockProcessing()
    }

    /// Dismiss a Complete/Failed state back to Idle.
    func dismiss() {
        cancelWork()
        phase = .idle
        elapsed = 0
        progress = 0
        generatedTitle = nil
        announce = false
        levels = Array(repeating: 0, count: Self.meterSampleCount)
    }

    /// Debug hook: jump straight to a phase to preview its appearance.
    func jump(to target: SessionPhase) {
        cancelWork()
        phase = target
        switch target {
        case .recording:
            elapsed = 754
            startTicking()
        case .processing:
            elapsed = 754
            progress = 0.6
        case .complete:
            elapsed = 754
            generatedTitle = "Codex-only Notes Kickoff"
        default:
            break
        }
        if target == .idle { announce = false } else { announceBriefly(5) }

        switch target {
        case .recording: SoundPlayer.shared.play(.doublePop)
        default: break
        }
    }

    // MARK: - Mock engine

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard phase.isRecording else { continue }
                elapsed += 0.1
                pushLevel(smoothedLevel())
            }
        }
    }

    private func runMockProcessing() {
        pipeline = Task { @MainActor in
            for stage in ProcessingStage.allCases {
                phase = .processing(stage)
                let steps = 10
                for i in 0...steps {
                    progress = Double(i) / Double(steps)
                    try? await Task.sleep(for: .milliseconds(80))
                    if Task.isCancelled { return }
                }
            }
            generatedTitle = "Codex-only Notes Kickoff"
            phase = .complete
            announceBriefly()
        }
    }

    /// Force-expand the Dot for a few seconds, then return to hover-driven mode.
    private func announceBriefly(_ seconds: Double = 4) {
        announce = true
        announceTask?.cancel()
        announceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { announce = false }
        }
    }

    private var lastLevel: Double = 0
    private func smoothedLevel() -> Double {
        let target = Double.random(in: 0.1...0.95)
        lastLevel += (target - lastLevel) * 0.4
        return min(max(lastLevel, 0), 1)
    }

    private func pushLevel(_ value: Double) {
        levels.removeFirst()
        levels.append(value)
    }

    private func cancelWork() {
        ticker?.cancel(); ticker = nil
        pipeline?.cancel(); pipeline = nil
        announceTask?.cancel(); announceTask = nil
    }
}
