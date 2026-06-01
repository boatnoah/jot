import XCTest
@testable import Jot

/// End-to-end check of the real `CodexAgent`: resolves the executable, runs a
/// preflight, and generates notes from a fixture transcript. This makes a real
/// (token-spending, network) Codex call, so it's opt-in — set
/// `JOT_RUN_CODEX_TESTS=1` to run it. It is NOT part of the default suite.
final class CodexAgentIntegrationTests: XCTestCase {
    func testGeneratesNotesFromTranscript() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["JOT_RUN_CODEX_TESTS"] == "1",
            "Set JOT_RUN_CODEX_TESTS=1 to run the real Codex integration test.")

        let agent = try XCTUnwrap(NotesAgentKind.codex.makeAgent(), "codex not found on PATH")

        let status = try await agent.preflight()
        XCTAssertTrue(status.isReady, "Codex not ready: \(status.detail)")

        let transcript = """
        User [00:00]: Let us ship the setup wizard on Friday.
        Others [00:06]: Agreed. I will handle QA on the permission flow.
        User [00:12]: I will write the ADR for the agent abstraction.
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jot-test-transcript-\(UUID().uuidString).md")
        try transcript.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let metadata = MeetingMetadata(
            sessionId: UUID(), startedAt: Date(), stoppedAt: Date(),
            elapsedSeconds: 12, whisperModel: "small.en", agentUsed: "Codex",
            generatedTitle: nil)

        let notes = try await agent.generateNotes(transcriptURL: url, metadata: metadata)
        XCTAssertTrue(notes.contains("## Summary"), "Notes missing Summary section:\n\(notes)")
        XCTAssertTrue(notes.contains("## Action Items"), "Notes missing Action Items section:\n\(notes)")
    }
}
