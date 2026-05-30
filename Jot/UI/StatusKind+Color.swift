import SwiftUI

extension StatusKind {
    var color: Color {
        switch self {
        case .idle: return Color(white: 0.62)
        case .active: return .red
        case .paused: return .orange
        case .processing: return .blue
        case .success: return .green
        case .failure: return .red
        }
    }
}
