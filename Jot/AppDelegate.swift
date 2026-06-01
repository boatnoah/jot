import AppKit
import Observation
import SwiftUI

/// Owns the shared AppState, the menu bar icon (quit-only, state-tinted), and
/// the floating Jot Dot window. The menu bar carries no control panel — all
/// controls live in the Dot.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let app = AppState()
    private let setup = SetupState()
    private var statusItem: NSStatusItem?
    private var dotWindow: DotWindow?
    private var setupWindow: SetupWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When the app is the test host, don't spin up the menu bar / setup
        // window — unit tests just need the module loaded.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

        setUpStatusItem()
        observePhase()

        // First-run setup is a gate: silently re-verify every check, then either
        // resume setup or, if everything passes, go straight to the ready state
        // and show the Dot for the first time (CONTEXT.md → First-Run Setup).
        Task { @MainActor in
            await setup.probeAll()
            if setup.isComplete {
                enterReadyState()
            } else {
                presentSetup()
            }
        }
    }

    // MARK: - Menu bar (quit-only)

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        updateStatusIcon()
        // The menu is set once setup state is known (setup menu vs ready menu).
    }

    /// Menu while setup is incomplete: just reopen setup, or quit.
    private func makeSetupMenu() -> NSMenu {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Setup…", action: #selector(openSetupMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        #if DEBUG
        let preview = NSMenuItem(title: "Preview Setup Flow", action: #selector(previewSetupFlow), keyEquivalent: "")
        preview.target = self
        menu.addItem(preview)
        #endif
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Jot", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    /// Full menu once setup is complete (debug previews + quit).
    private func makeReadyMenu() -> NSMenu {
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

        // Debug: audition each bundled sound.
        let sounds = NSMenu()
        for sound in Sound.allCases {
            let item = NSMenuItem(title: sound.displayName, action: #selector(playSound(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = Box(sound)
            sounds.addItem(item)
        }
        let soundItem = NSMenuItem(title: "Play Sound", action: nil, keyEquivalent: "")
        soundItem.submenu = sounds
        menu.addItem(soundItem)

        #if DEBUG
        let preview = NSMenuItem(title: "Preview Setup Flow", action: #selector(previewSetupFlow), keyEquivalent: "")
        preview.target = self
        menu.addItem(preview)
        #endif

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

    @objc private func playSound(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Box<Sound> else { return }
        SoundPlayer.shared.play(box.value)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func openSetupMenu() {
        Task { @MainActor in
            await setup.probeAll()
            if setup.isComplete {
                enterReadyState()
            } else {
                presentSetup()
            }
        }
    }

    // MARK: - First-run setup gate

    /// Present the real setup gate: reduce the menu, hide the Dot (nothing to
    /// record yet), and bring up the window.
    private func presentSetup() {
        statusItem?.menu = makeSetupMenu()
        dotWindow?.orderOut(nil)
        showSetupWindow()
    }

    /// Bring up the setup window as a real focusable window. A menu-bar accessory
    /// app must switch to `.regular` activation for a normal window to come to
    /// the front and accept focus during OS permission prompts.
    private func showSetupWindow() {
        NSApp.setActivationPolicy(.regular)
        let window = setupWindow ?? SetupWindow(state: setup, onComplete: { [weak self] in
            self?.finishSetup()
        })
        window.delegate = self
        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Finish from the window (the "Start using Jot" button): order out, then
    /// settle into whatever state we should now be in.
    private func finishSetup() {
        setupWindow?.orderOut(nil)
        setupWindowClosed()
    }

    /// Resolve app state after the setup window goes away (whether finished,
    /// closed mid-gate, or exiting a debug preview): if setup actually passes,
    /// go to the ready state; otherwise recede to the menu bar with setup still
    /// reopenable.
    private func setupWindowClosed() {
        #if DEBUG
        setup.endPreview()
        #endif
        if setup.isComplete {
            enterReadyState()
        } else {
            NSApp.setActivationPolicy(.accessory)
            statusItem?.menu = makeSetupMenu()
            dotWindow?.orderOut(nil)
        }
    }

    /// The post-setup steady state: accessory app, full menu, Dot visible.
    private func enterReadyState() {
        NSApp.setActivationPolicy(.accessory)
        statusItem?.menu = makeReadyMenu()
        showDot()
    }

    /// Closing the setup window (red button) routes through the same resolution
    /// as finishing. `finishSetup` uses `orderOut`, not `close`, so it never
    /// double-fires this.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === setupWindow else { return }
        setupWindowClosed()
    }

    #if DEBUG
    /// Debug: page through every setup step + the completion screen for design
    /// review, without granting permissions or downloading anything.
    @objc private func previewSetupFlow() {
        setup.startPreview()
        showSetupWindow()
    }
    #endif

    // MARK: - Dot window

    private func showDot() {
        if let dotWindow {
            dotWindow.orderFrontRegardless()
            return
        }
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

        // Idle uses a custom colored pencil (yellow body, red eraser) rather
        // than a monochrome SF Symbol — distinctive and on-brand for Jot.
        if case .idle = app.phase {
            button.image = PencilIcon.image()
            button.contentTintColor = nil
            return
        }

        let symbol: String
        switch app.phase {
        case .idle: symbol = "pencil"        // unreachable; handled above
        case .recording: symbol = "mic.circle.fill"
        case .paused: symbol = "pause.circle"
        case .processing: symbol = "circle.dotted"
        case .complete: symbol = "checkmark.circle.fill"
        case .failed: symbol = "exclamationmark.circle.fill"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Jot")
        image?.isTemplate = false
        button.image = image
        button.contentTintColor = app.phase.status.nsColor
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
