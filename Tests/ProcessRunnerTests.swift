import XCTest
@testable import Jot

/// Verifies the shared `ProcessRunner` primitive against tiny system binaries —
/// fast, deterministic, no network. These cover the mechanics every CLI adapter
/// depends on: stdout/stderr capture, exit codes, stdin piping (including a
/// payload large enough that a naive blocking write would deadlock), and the
/// timeout.
final class ProcessRunnerTests: XCTestCase {
    func testCapturesStdoutAndExitCode() async throws {
        let result = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello"],
            timeout: .seconds(5))
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testPipesStdin() async throws {
        // `cat` with no args echoes stdin to stdout.
        let result = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/cat"),
            arguments: [],
            stdin: Data("piped input".utf8),
            timeout: .seconds(5))
        XCTAssertEqual(result.stdoutString, "piped input")
    }

    func testLargeStdinDoesNotDeadlock() async throws {
        // Well past a 64 KB pipe buffer — a blocking stdin write would hang.
        let payload = String(repeating: "x", count: 500_000)
        let result = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/cat"),
            arguments: [],
            stdin: Data(payload.utf8),
            timeout: .seconds(20))
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.count, 500_000)
    }

    func testCapturesStderrAndNonZeroExit() async throws {
        let result = try await ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo oops 1>&2; exit 3"],
            timeout: .seconds(5))
        XCTAssertEqual(result.exitCode, 3)
        XCTAssertEqual(result.stderrString.trimmingCharacters(in: .whitespacesAndNewlines), "oops")
    }

    func testTimeoutTerminatesAndThrows() async throws {
        do {
            _ = try await ProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["10"],
                timeout: .milliseconds(300))
            XCTFail("Expected a timeout")
        } catch let error as ProcessRunnerError {
            XCTAssertEqual(error, .timedOut)
        }
    }
}
