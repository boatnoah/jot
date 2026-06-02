import Foundation

/// Generates notes by invoking the user's authenticated `codex` CLI
/// non-interactively (`codex exec`). The transcript is delivered on stdin (it
/// can exceed argv limits) and the agent's final message is captured via
/// `--output-last-message` to a temp file — clean Markdown with none of the
/// streamed event noise. Read-only sandbox + ephemeral session: this is a pure
/// text task, so the agent never touches the user's files.
struct CodexAgent: NotesAgent {
    var displayName: String { "Codex" }

    /// Resolved during setup (CONTEXT.md → First-Run Setup, "Detect codex").
    var executableURL: URL

    /// Hardcoded for now; will become configurable (CONTEXT.md → Notes Agent).
    var timeout: Duration = .seconds(300)

    /// The one-word title call is tiny, so it gets a much shorter leash.
    var titleTimeout: Duration = .seconds(60)

    func preflight() async throws -> AgentStatus {
        // `codex login status` is a cheap, no-token auth probe.
        let result: ProcessResult
        do {
            result = try await ProcessRunner.run(
                executableURL: executableURL,
                arguments: ["login", "status"],
                environment: ExecutableLocator.augmentedEnvironment(),
                timeout: .seconds(20))
        } catch {
            throw NotesAgentError.executableNotFound
        }
        let out = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0 else {
            // Prefer stderr when stdout is empty — surfaces the real cause (e.g.
            // "env: node: No such file or directory") rather than a guess.
            let err = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = !out.isEmpty ? out : (!err.isEmpty ? err : "Not signed in to Codex.")
            return AgentStatus(isReady: false, detail: detail)
        }
        return AgentStatus(isReady: true, detail: out.isEmpty ? "Signed in to Codex." : out)
    }

    func generateNotes(transcriptURL: URL, metadata: MeetingMetadata) async throws -> String {
        let transcript = try String(contentsOf: transcriptURL, encoding: .utf8)

        // Context cap pre-flight (CONTEXT.md → Context Cap): terminal, no retry,
        // transcript already saved.
        guard transcript.count <= NotesPrompt.maxTranscriptCharacters else {
            throw NotesAgentError.transcriptTooLarge
        }

        let outputFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("jot-notes-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: outputFile) }

        let result = try await ProcessRunner.run(
            executableURL: executableURL,
            arguments: [
                "exec",
                "--skip-git-repo-check",   // the notes folder isn't a git repo
                "--sandbox", "read-only",  // pure text task; never writes
                "--ephemeral",             // don't persist a session
                "--output-last-message", outputFile.path,
                NotesPrompt.instructions(metadata: metadata),
            ],
            stdin: Data(transcript.utf8),
            environment: ExecutableLocator.augmentedEnvironment(),
            timeout: timeout)

        guard result.exitCode == 0 else {
            let stderr = result.stderrString.lowercased()
            if stderr.contains("login") || stderr.contains("auth") {
                throw NotesAgentError.notAuthenticated
            }
            let detail = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NotesAgentError.generationFailed(detail.isEmpty ? "Codex exited with code \(result.exitCode)." : detail)
        }

        // Prefer the captured final message; fall back to stdout if absent.
        let captured = (try? String(contentsOf: outputFile, encoding: .utf8)) ?? result.stdoutString
        let notes = captured.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else {
            throw NotesAgentError.generationFailed("Codex returned no notes.")
        }
        return notes
    }

    /// Override the agent-agnostic default with a dedicated one-word title call:
    /// the notes go in on stdin and Codex replies with a single word, which we
    /// reduce to a clean folder-safe token. Best-effort by contract — the caller
    /// (SessionController) treats any throw as "keep the datestamp name".
    func generateTitle(fromNotes notes: String, metadata: MeetingMetadata) async throws -> String {
        let outputFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("jot-title-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outputFile) }

        let result = try await ProcessRunner.run(
            executableURL: executableURL,
            arguments: [
                "exec",
                "--skip-git-repo-check",
                "--sandbox", "read-only",
                "--ephemeral",
                "--output-last-message", outputFile.path,
                NotesPrompt.titleInstructions,
            ],
            stdin: Data(notes.utf8),
            environment: ExecutableLocator.augmentedEnvironment(),
            timeout: titleTimeout)

        guard result.exitCode == 0 else {
            let detail = result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
            throw NotesAgentError.generationFailed(detail.isEmpty ? "Codex exited with code \(result.exitCode)." : detail)
        }

        let captured = (try? String(contentsOf: outputFile, encoding: .utf8)) ?? result.stdoutString
        guard let word = NotesTitle.singleWord(from: captured) else {
            throw NotesAgentError.generationFailed("Codex returned no usable title.")
        }
        return word
    }
}

extension ProcessRunnerError {
    /// Map the shared runner's timeout onto the notes-agent vocabulary so callers
    /// can present a consistent failure.
    var asNotesAgentError: NotesAgentError {
        switch self {
        case .timedOut: return .timedOut
        case .launchFailed: return .executableNotFound
        }
    }
}
