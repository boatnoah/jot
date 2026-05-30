import Foundation

/// A bundled audio file. Files live in `Resources/` and ship in the app bundle.
enum Sound: String, CaseIterable {
    case doublePop = "doublepop"
    case keyTap = "keytap"

    var displayName: String {
        switch self {
        case .doublePop: return "doublepop"
        case .keyTap: return "keytap (typing)"
        }
    }

    var url: URL? {
        Bundle.main.url(forResource: rawValue, withExtension: "mp3")
    }
}
