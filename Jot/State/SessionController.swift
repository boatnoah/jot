import Foundation

/// Drives one capture session end-to-end behind `AppState`'s observable surface:
/// record → streaming transcription → `transcript.md` → notes → `notes.md` →
/// complete (+ folder rename to the generated title). Every failure maps to the
/// matching `SessionPhase.failed(kind)`; the transcript and audio are the durable
/// guarantee, so notes/title failures never discard them (CONTEXT.md → Failure
/// Modes, Recording Folder).
///
/// Dependencies are injected (with production defaults) so the whole flow is
/// testable with fakes. The controller reports state purely through its
/// callbacks — it never touches UI — so `AppState`/`DotView` stay unchanged.
@MainActor
final class SessionController {
    // MARK: - Injected dependencies

    private let notesDirectory: URL
    private let makeCapturers: () -> [any AudioCapturing]
    private let transcriber: (any Transcriber)?
    private let makeAgent: () -> (any NotesAgent)?
    private let chunkSeconds: TimeInterval

    // MARK: - Callbacks (set by AppState)

    var onPhase: ((SessionPhase) -> Void)?
    var onElapsed: ((TimeInterval) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onProgress: ((Double) -> Void)?
    var onTitle: ((String) -> Void)?

    // MARK: - Per-session state

    private var store: SessionStore?
    private var recorder: AudioRecorder?
    private var metadata: MeetingMetadata?
    private var capturing = false
    private var lastElapsed: TimeInterval = 0
    /// One transcription task per closed chunk, keyed by chunk index so results
    /// merge in a stable order. Each task transcribes both the chunk's mic and
    /// system files and returns their segments.
    private var transcriptionTasks: [Int: Task<[TranscriptSegment], Error>] = [:]
    private var processing: Task<Void, Never>?

    init(
        notesDirectory: URL,
        makeCapturers: @escaping () -> [any AudioCapturing] = { [MicCapture(), SystemAudioCapture()] },
        transcriber: (any Transcriber)? = WhisperCppTranscriber.makeDefault(),
        makeAgent: @escaping () -> (any NotesAgent)? = { NotesAgentKind.makeSelectedAgent() },
        chunkSeconds: TimeInterval = 30
    ) {
        self.notesDirectory = notesDirectory
        self.makeCapturers = makeCapturers
        self.transcriber = transcriber
        self.makeAgent = makeAgent
        self.chunkSeconds = chunkSeconds
    }

    // MARK: - Finished-session artifacts (for the Complete-state actions)

    /// The session's Recording Folder, reflecting the title rename. Nil before a
    /// session exists and after `dismiss()`.
    var folderURL: URL? { store?.url }
    /// The generated `notes.md` inside the Recording Folder.
    var notesURL: URL? { store?.notesURL }

    // MARK: - Lifecycle

    func start() {
        reset()
        let startedAt = Date()
        let store: SessionStore
        do {
            store = try SessionStore(notesDirectory: notesDirectory, startedAt: startedAt)
        } catch {
            onPhase?(.failed(.recording))
            return
        }
        self.store = store

        let meta = MeetingMetadata(
            sessionId: UUID(),
            startedAt: startedAt,
            stoppedAt: nil,
            elapsedSeconds: 0,
            whisperModel: WhisperCppTranscriber.modelFileName,
            agentUsed: NotesAgentKind.selected.displayName,
            generatedTitle: nil)
        self.metadata = meta
        try? store.writeMetadata(meta)

        let recorder = AudioRecorder(
            directory: store.url,
            capturers: makeCapturers(),
            chunkSeconds: chunkSeconds)
        // Recorder callbacks arrive on the main queue (DispatchQueue.main.async),
        // i.e. the MainActor's executor, so we can assume isolation rather than
        // hop through another Task — that keeps chunk ordering deterministic.
        recorder.onElapsed = { [weak self] elapsed in
            MainActor.assumeIsolated { self?.handleElapsed(elapsed) }
        }
        recorder.onLevel = { [weak self] level in
            MainActor.assumeIsolated { self?.onLevel?(level) }
        }
        recorder.onChunkClosed = { [weak self] chunk in
            MainActor.assumeIsolated { self?.enqueueTranscription(chunk) }
        }
        recorder.onMicSilent = {
            NSLog("[SessionController] microphone delivered only silence this session.")
        }
        self.recorder = recorder

        Task { @MainActor in
            do {
                try await recorder.start()
                self.capturing = true
                self.onPhase?(.recording)
            } catch {
                self.capturing = false
                self.onPhase?(.failed(.recording))
            }
        }
    }

    func pause() {
        recorder?.pause()
        onPhase?(.paused)
    }

    func resume() {
        recorder?.resume()
        onPhase?(.recording)
    }

    func stop() {
        guard let recorder, let store else { return }
        onPhase?(.processing(.finalizingAudio))
        // Enqueue the final chunk's transcription before draining: it closes
        // synchronously inside stop(), so the recorder hands it back directly
        // rather than via the async streaming hook (see AudioRecorder.stop).
        let finalChunk = recorder.stop()
        capturing = false
        if let finalChunk { enqueueTranscription(finalChunk) }

        let stoppedAt = Date()
        let elapsedSeconds = lastElapsed
        processing = Task { @MainActor in
            await self.runProcessing(store: store, stoppedAt: stoppedAt, elapsedSeconds: elapsedSeconds)
        }
    }

    /// Return a Complete/Failed session to Idle.
    func dismiss() {
        reset()
        onPhase?(.idle)
    }

    // MARK: - Streaming transcription

    private func handleElapsed(_ elapsed: TimeInterval) {
        lastElapsed = elapsed
        onElapsed?(elapsed)
    }

    private func enqueueTranscription(_ chunk: ClosedChunk) {
        guard let transcriber else { return }   // surfaced as .transcription at drain
        transcriptionTasks[chunk.index] = Task {
            async let mic = transcriber.transcribe(
                audioChunk: chunk.micURL, source: .microphone, elapsedOffset: chunk.elapsedOffset)
            async let system = transcriber.transcribe(
                audioChunk: chunk.systemURL, source: .system, elapsedOffset: chunk.elapsedOffset)
            return try await mic + system
        }
    }

    // MARK: - Processing pipeline (post-Stop)

    private func runProcessing(store: SessionStore, stoppedAt: Date, elapsedSeconds: TimeInterval) async {
        // 1. Transcribing — drain every chunk task, tracking progress.
        onPhase?(.processing(.transcribing))
        onProgress?(0)
        guard transcriber != nil else { onPhase?(.failed(.transcription)); return }

        let ordered = transcriptionTasks.sorted { $0.key < $1.key }
        let total = max(ordered.count, 1)
        var segments: [TranscriptSegment] = []
        var done = 0
        for (_, task) in ordered {
            do {
                segments.append(contentsOf: try await task.value)
            } catch {
                onPhase?(.failed(.transcription))   // audio kept
                return
            }
            done += 1
            onProgress?(Double(done) / Double(total))
        }

        // 2. Saving transcript.
        onPhase?(.processing(.savingTranscript))
        do {
            try store.writeTranscript(TranscriptBuilder.render(segments))
        } catch {
            onPhase?(.failed(.transcription))   // audio kept
            return
        }
        var meta = metadata ?? MeetingMetadata(
            sessionId: UUID(), startedAt: stoppedAt, stoppedAt: nil, elapsedSeconds: 0,
            whisperModel: WhisperCppTranscriber.modelFileName,
            agentUsed: NotesAgentKind.selected.displayName, generatedTitle: nil)
        meta.stoppedAt = stoppedAt
        meta.elapsedSeconds = elapsedSeconds
        metadata = meta
        try? store.writeMetadata(meta)

        // 3. Generating notes.
        onPhase?(.processing(.generatingNotes))
        guard let agent = makeAgent() else { onPhase?(.failed(.notes)); return }
        let notes: String
        do {
            notes = try await agent.generateNotes(transcriptURL: store.transcriptURL, metadata: meta)
        } catch NotesAgentError.transcriptTooLarge {
            onPhase?(.failed(.transcriptTooLarge))   // terminal, transcript saved
            return
        } catch {
            onPhase?(.failed(.notes))                // transcript saved
            return
        }
        do {
            try store.writeNotes(notes)
        } catch {
            onPhase?(.failed(.notes))
            return
        }

        // 4. Title — best-effort. Failure just keeps the datestamp folder name.
        if let title = try? await agent.generateTitle(fromNotes: notes, metadata: meta),
           !title.isEmpty {
            meta.generatedTitle = title
            metadata = meta
            try? store.writeMetadata(meta)
            try? store.rename(toTitle: title)
            onTitle?(title)
        }

        onPhase?(.complete)
    }

    // MARK: - Teardown

    private func reset() {
        processing?.cancel()
        processing = nil
        if capturing { recorder?.stop() }
        capturing = false
        recorder = nil
        for (_, task) in transcriptionTasks { task.cancel() }
        transcriptionTasks.removeAll()
        store = nil
        metadata = nil
        lastElapsed = 0
    }
}
