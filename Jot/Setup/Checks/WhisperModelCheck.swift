import Foundation

/// Step 6 — download and verify the Whisper `small.en` model (~465 MB). This is
/// the only heavy step and the reason setup is a window: it needs a real
/// progress bar (CONTEXT.md → First-Run Setup). The model is stored under
/// Application Support, matching the project decision.
///
/// `probe()` is real (the file's presence and size). `act()` performs a real
/// streamed download reporting progress. The source URL and the integrity check
/// are still provisional — see the TODOs.
@MainActor
@Observable
final class WhisperModelCheck: SetupCheck {
    nonisolated let step = SetupStep.whisperModel
    private(set) var status: CheckStatus = .unsatisfied

    let headline = "Grab the speech model"
    let body = "Jot transcribes on your Mac with a ~465 MB model — a one-time download. Good time for a coffee."
    let actionTitle = "Download model"

    /// Friendly "120 / 465 MB" label shown under the progress bar; `nil` otherwise.
    private(set) var detail: String?

    // MARK: - Model location & source

    // The on-disk location is owned by the pipeline (where the transcriber reads
    // it from); this check only handles downloading to that location.
    private static var modelsDirectory: URL { WhisperCppTranscriber.modelsDirectory }
    private static var modelURL: URL { WhisperCppTranscriber.defaultModelURL }

    // TODO(model-source): confirm this URL + add SHA-256 verification and a
    // resume-on-interrupt path. Defaulting to the whisper.cpp ggml model on
    // Hugging Face per the brainstorm.
    private static let sourceURL = URL(
        string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"
    )!

    /// Heuristic floor for "looks like a complete model" until SHA verification
    /// lands. The real file is ~465 MB.
    private static let minExpectedBytes: Int64 = 400_000_000

    // MARK: - Probe

    func probe() async {
        let url = Self.modelURL
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.size] as? Int64 else {
            status = .unsatisfied
            return
        }
        // TODO(model-source): replace the size floor with a SHA-256 match.
        status = size >= Self.minExpectedBytes
            ? .satisfied
            : .failed("The model file looks incomplete. Download it again.")
    }

    // MARK: - Download

    /// Retained for the lifetime of the download (owns the URLSession + delegate).
    private var downloader: ModelDownloader?

    func act() async {
        status = .running(0)
        detail = nil
        do {
            try FileManager.default.createDirectory(
                at: Self.modelsDirectory, withIntermediateDirectories: true)

            let downloader = ModelDownloader()
            self.downloader = downloader
            defer { self.downloader = nil }

            for try await event in downloader.download(from: Self.sourceURL, to: Self.modelURL) {
                try Task.checkCancellation()
                switch event {
                case .progress(let fraction, let received, let total):
                    status = .running(fraction)
                    detail = total > 0
                        ? "\(received / 1_000_000) / \(total / 1_000_000) MB"
                        : "\(received / 1_000_000) MB"
                case .finished:
                    detail = nil
                }
            }
            await probe()
        } catch is CancellationError {
            status = .unsatisfied
            detail = nil
        } catch {
            status = .failed("Download failed: \(error.localizedDescription)")
            detail = nil
        }
    }
}
