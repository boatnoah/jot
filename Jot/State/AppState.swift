import AppKit
import Foundation
import Observation

/// Observable session state for the Jot Dot. Owns a `SessionController` that does
/// the real work (record → transcribe → notes) and forwards its callbacks onto
/// the exact properties `DotView` binds to, so the UI layer is unchanged. The
/// debug `jump(to:)` stays a pure UI preview that never touches the controller.
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

    /// Title the notes agent produced for the session; set on Complete.
    private(set) var generatedTitle: String?

    static let meterSampleCount = 18

    private let controller: SessionController
    private var announceTask: Task<Void, Never>?
    /// Drives the level meter / clock for the debug `jump(to:)` preview only —
    /// real recording feeds `elapsed`/`levels` from the controller's callbacks.
    private var previewTicker: Task<Void, Never>?

    init(controller: SessionController? = nil) {
        self.controller = controller ?? SessionController(notesDirectory: Self.resolvedNotesDirectory())
        wireController()
    }

    // MARK: - User actions

    func start() {
        previewTicker?.cancel(); previewTicker = nil
        elapsed = 0
        progress = 0
        generatedTitle = nil
        levels = Array(repeating: 0, count: Self.meterSampleCount)
        // Optimistic so the Dot responds instantly; the controller confirms with
        // .recording (or corrects to .failed if capture can't start).
        phase = .recording
        // Plays before capture begins, so it never bleeds into the recording.
        SoundPlayer.shared.play(.doublePop)
        controller.start()
        // Briefly force-expand so the user confirms capture is live.
        announceBriefly()
    }

    func pause() {
        guard phase.isRecording else { return }
        controller.pause()
    }

    func resume() {
        guard phase == .paused else { return }
        controller.resume()
    }

    func stop() {
        guard phase.isRecording || phase == .paused else { return }
        // Plays after capture has stopped — the "now working on it" cue.
        SoundPlayer.shared.play(.keyTap)
        controller.stop()
    }

    /// Dismiss a Complete/Failed state back to Idle.
    func dismiss() {
        controller.dismiss()
        previewTicker?.cancel(); previewTicker = nil
        announceTask?.cancel(); announceTask = nil
        elapsed = 0
        progress = 0
        generatedTitle = nil
        announce = false
        levels = Array(repeating: 0, count: Self.meterSampleCount)
    }

    // MARK: - Complete-state actions

    /// Open the generated notes in the user's default Markdown handler.
    func openNotes() {
        guard let url = controller.notesURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// Copy the notes' Markdown to the clipboard.
    func copyNotes() {
        guard let url = controller.notesURL,
              let markdown = try? String(contentsOf: url, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    /// Reveal the Recording Folder in Finder, with notes.md selected.
    func revealInFinder() {
        if let notes = controller.notesURL {
            NSWorkspace.shared.activateFileViewerSelecting([notes])
        } else if let folder = controller.folderURL {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    /// Debug hook: jump straight to a phase to preview its appearance. Pure UI —
    /// it never starts the real pipeline.
    func jump(to target: SessionPhase) {
        previewTicker?.cancel(); previewTicker = nil
        announceTask?.cancel(); announceTask = nil
        phase = target
        switch target {
        case .recording:
            elapsed = 754
            startPreviewTicker()
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
        if case .recording = target { SoundPlayer.shared.play(.doublePop) }
    }

    // MARK: - Controller wiring

    private func wireController() {
        controller.onPhase = { [weak self] phase in self?.handlePhase(phase) }
        controller.onElapsed = { [weak self] elapsed in self?.elapsed = elapsed }
        controller.onLevel = { [weak self] level in self?.pushLevel(level) }
        controller.onProgress = { [weak self] progress in self?.progress = progress }
        controller.onTitle = { [weak self] title in self?.generatedTitle = title }
    }

    private func handlePhase(_ newPhase: SessionPhase) {
        phase = newPhase
        switch newPhase {
        case .recording, .complete:
            announceBriefly()
        default:
            break
        }
    }

    // MARK: - Helpers

    /// Where sessions are stored. Set during first-run setup; falls back to
    /// ~/Documents/Jot if unset.
    private static func resolvedNotesDirectory() -> URL {
        if let path = UserDefaults.standard.string(forKey: "notesDirectoryPath"), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Jot", isDirectory: true)
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

    private func startPreviewTicker() {
        previewTicker?.cancel()
        previewTicker = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard phase.isRecording else { continue }
                elapsed += 0.1
                pushLevel(smoothedLevel())
            }
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
}
