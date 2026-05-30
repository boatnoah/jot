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

        // Idle uses a custom colored pencil (yellow body, red eraser) rather
        // than a monochrome SF Symbol — distinctive and on-brand for Jot.
        if case .idle = app.phase {
            button.image = Self.pencilImage()
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

    /// A small diagonal school pencil drawn in code: red eraser, silver ferrule,
    /// yellow body, wood tip with a graphite point. Non-template so it keeps its
    /// colors in the menu bar.
    private static func pencilImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // Draw a horizontal pencil centered at the origin, rotated 45°.
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: .pi / 4)

            let len: CGFloat = 15
            let h: CGFloat = 5
            let left = -len / 2, right = len / 2
            let top = h / 2, bottom = -h / 2

            // Boundaries left→right: wood tip | yellow body | ferrule | eraser.
            let woodEnd = left + 3.5
            let bodyEnd = right - 4.5
            let ferruleEnd = right - 2.8

            // Wood cone (tan).
            ctx.beginPath()
            ctx.move(to: CGPoint(x: left, y: 0))
            ctx.addLine(to: CGPoint(x: woodEnd, y: top))
            ctx.addLine(to: CGPoint(x: woodEnd, y: bottom))
            ctx.closePath()
            ctx.setFillColor(NSColor(calibratedRed: 0.85, green: 0.69, blue: 0.45, alpha: 1).cgColor)
            ctx.fillPath()

            // Graphite point (dark).
            ctx.beginPath()
            ctx.move(to: CGPoint(x: left, y: 0))
            ctx.addLine(to: CGPoint(x: left + 1.6, y: top * 0.45))
            ctx.addLine(to: CGPoint(x: left + 1.6, y: bottom * 0.45))
            ctx.closePath()
            ctx.setFillColor(NSColor(white: 0.13, alpha: 1).cgColor)
            ctx.fillPath()

            // Yellow body.
            ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.79, blue: 0.05, alpha: 1).cgColor)
            ctx.fill(CGRect(x: woodEnd, y: bottom, width: bodyEnd - woodEnd, height: h))

            // Silver ferrule.
            ctx.setFillColor(NSColor(white: 0.72, alpha: 1).cgColor)
            ctx.fill(CGRect(x: bodyEnd, y: bottom, width: ferruleEnd - bodyEnd, height: h))

            // Red eraser (rounded outer end).
            let eraser = CGRect(x: ferruleEnd, y: bottom, width: right - ferruleEnd, height: h)
            ctx.addPath(CGPath(roundedRect: eraser, cornerWidth: 1.6, cornerHeight: 1.6, transform: nil))
            ctx.setFillColor(NSColor(calibratedRed: 0.91, green: 0.27, blue: 0.22, alpha: 1).cgColor)
            ctx.fillPath()

            return true
        }
        image.isTemplate = false
        return image
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
