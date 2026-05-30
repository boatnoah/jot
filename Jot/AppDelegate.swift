import AppKit
import Observation
import SwiftUI

/// Owns the shared AppState, the menu bar icon (quit-only, state-tinted), and
/// the floating Jot Dot window. The menu bar carries no control panel — all
/// controls live in the Dot.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let app = AppState()
    private var statusItem: NSStatusItem?
    private var dotWindow: DotWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        showDot()
        observePhase()
    }

    // MARK: - Menu bar (quit-only)

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.menu = makeMenu()
        statusItem = item
        updateStatusIcon()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        // Debug: preview each visual state of the Dot.
        let debug = NSMenu()
        let states: [(String, SessionPhase)] = [
            ("Idle", .idle),
            ("Recording", .recording),
            ("Processing", .processing(.transcribing)),
            ("Complete", .complete),
            ("Failed: Transcription", .failed(.transcription)),
            ("Failed: Notes", .failed(.notes)),
            ("Failed: Too Large", .failed(.transcriptTooLarge)),
        ]
        for (title, phase) in states {
            let menuItem = NSMenuItem(title: title, action: #selector(jumpToState(_:)), keyEquivalent: "")
            menuItem.target = self
            menuItem.representedObject = Box(phase)
            debug.addItem(menuItem)
        }
        let debugItem = NSMenuItem(title: "Preview State", action: nil, keyEquivalent: "")
        debugItem.submenu = debug
        menu.addItem(debugItem)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Jot", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func jumpToState(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Box<SessionPhase> else { return }
        app.jump(to: box.value)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Dot window

    private func showDot() {
        let window = DotWindow(app: app)
        window.orderFrontRegardless()
        dotWindow = window
    }

    // MARK: - Icon state tinting

    /// Re-arming observation: updates the menu bar icon whenever the phase
    /// changes, then re-subscribes (withObservationTracking is single-shot).
    private func observePhase() {
        withObservationTracking {
            _ = app.phase
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateStatusIcon()
                self?.observePhase()
            }
        }
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbol: String
        switch app.phase {
        case .idle: symbol = "mic.circle"
        case .recording: symbol = "mic.circle.fill"
        case .paused: symbol = "pause.circle"
        case .processing: symbol = "circle.dotted"
        case .complete: symbol = "checkmark.circle.fill"
        case .failed: symbol = "exclamationmark.circle.fill"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Jot")
        image?.isTemplate = (app.phase.status == .idle)
        button.image = image
        button.contentTintColor = app.phase.status == .idle ? nil : app.phase.status.nsColor
    }
}

/// Reference box so a value-type phase can ride in `representedObject`.
private final class Box<T> {
    let value: T
    init(_ value: T) { self.value = value }
}

private extension StatusKind {
    var nsColor: NSColor {
        switch self {
        case .idle: return .secondaryLabelColor
        case .active: return .systemRed
        case .paused: return .systemOrange
        case .processing: return .systemBlue
        case .success: return .systemGreen
        case .failure: return .systemRed
        }
    }
}
