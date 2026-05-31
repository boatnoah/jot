import SwiftUI

/// Jot's brand palette, drawn from the pencil mark (see `PencilIcon`). The
/// pencil yellow is the signature accent for onboarding; the eraser red is
/// reserved for failures and celebratory beats (CONTEXT.md → First-Run Setup).
extension Color {
    /// Pencil body — #FFC90D. The one bold accent per setup screen.
    static let pencilYellow = Color(red: 1.0, green: 0.79, blue: 0.05)

    /// Eraser — #E84538. Failures and the finish.
    static let eraserRed = Color(red: 0.91, green: 0.27, blue: 0.22)
}
