import AVFoundation
import XCTest
@testable import Jot

/// Drives `SessionController` end-to-end with fakes for capture, transcription,
/// and the notes agent — asserting the happy path (transcript + notes written,
/// folder renamed to the derived title) and each failure mapping.
@MainActor
final class SessionControllerTests: XCTestCase {
    private var root: URL!
    private var phases: [SessionPhase] = []
    private var receivedTitle: String?

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sessioncontroller-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        phases = []
        receivedTitle = nil
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Happy path

    func testHappyPathWritesArtifactsAndRenamesFolder() async throws {
        let transcriber = FakeTranscriber(
            micSegments: [seg(.microphone, 1, "hi")],
            systemSegments: [seg(.system, 2, "hello there")])
        let controller = makeController(
            transcriber: transcriber,
            agent: FakeAgent(notes: "## Summary\nA quick sync."))

        try await run(controller)

        XCTAssertEqual(phases.last, .complete)
        XCTAssertEqual(receivedTitle, "A quick sync")

        let folder = try theOnlyFolder()
        XCTAssertTrue(folder.lastPathComponent.hasSuffix("A quick sync"),
                      "folder renamed to the derived title, got \(folder.lastPathComponent)")
        let transcript = try String(contentsOf: folder.appendingPathComponent("transcript.md"), encoding: .utf8)
        XCTAssertEqual(transcript, "[00:01] User: hi\n[00:02] Others: hello there")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("notes.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("metadata.json").path))
    }

    // MARK: - Failure mappings

    func testTranscriberFailureMapsToTranscriptionFailed() async throws {
        let controller = makeController(
            transcriber: FakeTranscriber(fails: true),
            agent: FakeAgent(notes: "## Summary\nx."))

        try await run(controller)

        XCTAssertEqual(phases.last, .failed(.transcription))
    }

    func testTranscriptTooLargeIsTerminal() async throws {
        let controller = makeController(
            transcriber: FakeTranscriber(micSegments: [seg(.microphone, 1, "hi")]),
            agent: FakeAgent(notes: "", notesError: .transcriptTooLarge))

        try await run(controller)

        XCTAssertEqual(phases.last, .failed(.transcriptTooLarge))
        // Transcript is the durable guarantee — it survives a notes failure.
        let folder = try theOnlyFolder()
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("transcript.md").path))
    }

    func testMissingAgentMapsToNotesFailed() async throws {
        let controller = SessionController(
            notesDirectory: root,
            makeCapturers: { [StubCapture(source: .microphone), StubCapture(source: .system)] },
            transcriber: FakeTranscriber(micSegments: [seg(.microphone, 1, "hi")]),
            makeAgent: { nil },
            chunkSeconds: 600)
        wire(controller)

        try await run(controller)

        XCTAssertEqual(phases.last, .failed(.notes))
    }

    func testAgentFailureMapsToNotesFailed() async throws {
        let controller = makeController(
            transcriber: FakeTranscriber(micSegments: [seg(.microphone, 1, "hi")]),
            agent: FakeAgent(notes: "", notesError: .generationFailed("boom")))

        try await run(controller)

        XCTAssertEqual(phases.last, .failed(.notes))
    }

    func testUnderivableTitleStillCompletesWithDatestampName() async throws {
        // "## Summary\nNone" derives no usable title, so the default throws and the
        // controller keeps the datestamp folder name — still a Complete session.
        let controller = makeController(
            transcriber: FakeTranscriber(micSegments: [seg(.microphone, 1, "hi")]),
            agent: FakeAgent(notes: "## Summary\nNone"))

        try await run(controller)

        XCTAssertEqual(phases.last, .complete)
        XCTAssertNil(receivedTitle)
        let folder = try theOnlyFolder()
        XCTAssertEqual(folder.lastPathComponent.count, "yyyy-MM-dd HH-mm".count,
                       "no title appended; got \(folder.lastPathComponent)")
    }

    // MARK: - Helpers

    private func makeController(transcriber: FakeTranscriber, agent: FakeAgent) -> SessionController {
        let controller = SessionController(
            notesDirectory: root,
            makeCapturers: { [StubCapture(source: .microphone), StubCapture(source: .system)] },
            transcriber: transcriber,
            makeAgent: { agent },
            chunkSeconds: 600)
        wire(controller)
        return controller
    }

    private func wire(_ controller: SessionController) {
        controller.onPhase = { [weak self] in self?.phases.append($0) }
        controller.onTitle = { [weak self] in self?.receivedTitle = $0 }
    }

    /// Start, let it record briefly, stop, and wait for a terminal phase.
    private func run(_ controller: SessionController) async throws {
        controller.start()
        try await waitUntil { self.phases.contains(.recording) || self.isTerminal }
        try await Task.sleep(for: .milliseconds(50))
        controller.stop()
        try await waitUntil { self.isTerminal }
    }

    private var isTerminal: Bool {
        switch phases.last {
        case .complete, .failed: return true
        default: return false
        }
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { XCTFail("timed out; phases=\(phases)"); return }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func theOnlyFolder() throws -> URL {
        let dirs = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        XCTAssertEqual(dirs.count, 1, "expected exactly one session folder")
        return dirs[0]
    }

    private func seg(_ source: AudioSource, _ start: TimeInterval, _ text: String) -> TranscriptSegment {
        TranscriptSegment(source: source, startElapsed: start, endElapsed: start + 1, text: text)
    }
}

// MARK: - Fakes

private struct FakeTranscriber: Transcriber {
    var micSegments: [TranscriptSegment] = []
    var systemSegments: [TranscriptSegment] = []
    var fails = false

    func transcribe(audioChunk: URL, source: AudioSource, elapsedOffset: TimeInterval) async throws -> [TranscriptSegment] {
        if fails { throw TranscriberError.transcriptionFailed("fake failure") }
        return source == .microphone ? micSegments : systemSegments
    }
}

private final class FakeAgent: NotesAgent, @unchecked Sendable {
    var displayName: String { "Fake" }
    let notes: String
    let notesError: NotesAgentError?

    init(notes: String, notesError: NotesAgentError? = nil) {
        self.notes = notes
        self.notesError = notesError
    }

    func preflight() async throws -> AgentStatus { AgentStatus(isReady: true, detail: "ready") }

    func generateNotes(transcriptURL: URL, metadata: MeetingMetadata) async throws -> String {
        if let notesError { throw notesError }
        return notes
    }
    // generateTitle uses the protocol default (local derive from notes).
}

/// An `AudioCapturing` that starts/stops cleanly but emits no buffers — the real
/// `AudioRecorder` + `ChunkWriter` still create the (empty) chunk files, and the
/// injected `FakeTranscriber` supplies the segments, so no audio is needed.
private final class StubCapture: AudioCapturing, @unchecked Sendable {
    let source: AudioSource
    init(source: AudioSource) { self.source = source }
    func start(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) async throws {}
    func stop() {}
}
