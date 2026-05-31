import AppKit
import SwiftUI

/// Hosts the first-run setup wizard. A normal titled macOS window (traffic
/// lights visible, so it reads as a legit Mac window during OS permission
/// grants) but forced to a dark appearance so it never clashes with the rest of
/// the app (CONTEXT.md → First-Run Setup). Fixed size; not released on close so
/// it can be reopened from the menu bar.
@MainActor
final class SetupWindow: NSWindow {
    init(state: SetupState, onComplete: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        title = "Jot Setup"
        titlebarAppearsTransparent = true
        // Draggable by its title bar only. Background dragging swallows clicks on
        // transparent SwiftUI controls (e.g. the plain preview Prev/Next buttons).
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        // Forced dark, independent of the system light/dark setting.
        appearance = NSAppearance(named: .darkAqua)

        let host = NSHostingView(rootView: SetupView(state: state, onComplete: onComplete))
        host.frame = contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        contentView?.addSubview(host)

        center()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
