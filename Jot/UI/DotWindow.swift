import AppKit
import SwiftUI

/// Borderless, always-on-top, draggable panel that hosts the Jot Dot. It is a
/// non-activating floating panel so interacting with it never steals focus from
/// the user's meeting window, yet its buttons remain clickable.
@MainActor
final class DotWindow: NSPanel {
    init(app: AppState) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let host = NSHostingView(rootView: DotView(app: app))
        host.frame = contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        contentView?.addSubview(host)

        positionAtBottomTrailing()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func positionAtBottomTrailing() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let margin: CGFloat = 24
        let origin = NSPoint(
            x: visible.maxX - frame.width - margin,
            y: visible.minY + margin
        )
        setFrameOrigin(origin)
    }
}
