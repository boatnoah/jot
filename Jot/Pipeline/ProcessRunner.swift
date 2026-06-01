import Foundation

/// Output of a finished subprocess.
struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data

    var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

enum ProcessRunnerError: Error, Equatable {
    case launchFailed(String)
    case timedOut
}

/// Async, cancellable wrapper around `Process` — the shared primitive behind
/// every CLI adapter (notes agents, whisper-cli, setup preflight). It pipes
/// optional stdin, drains stdout/stderr concurrently so a full pipe can't
/// deadlock the child, enforces a timeout, and terminates the child if the
/// surrounding task is cancelled. No shell, no string interpolation — arguments
/// are passed as an explicit array.
enum ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        stdin: Data? = nil,
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        timeout: Duration
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        let box = ProcessBox(process)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ProcessResult, Error>) in
                let state = RunState(continuation: cont)

                // Accumulate output as it arrives; empty data signals EOF.
                outPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        state.markStdoutEOF()
                    } else {
                        state.appendStdout(data)
                    }
                }
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty {
                        handle.readabilityHandler = nil
                        state.markStderrEOF()
                    } else {
                        state.appendStderr(data)
                    }
                }

                process.terminationHandler = { proc in
                    state.markExited(status: proc.terminationStatus)
                }

                do {
                    try process.run()
                } catch {
                    state.fail(.launchFailed(error.localizedDescription))
                    return
                }

                // Write stdin off-thread so a >64 KB payload (a large transcript)
                // can't block waiting on a child that drains stdin lazily.
                let writeHandle = inPipe.fileHandleForWriting
                if let stdin {
                    DispatchQueue.global().async {
                        try? writeHandle.write(contentsOf: stdin)
                        try? writeHandle.close()
                    }
                } else {
                    try? writeHandle.close()
                }

                // Timeout: terminate the child and fail (idempotent — RunState
                // resumes the continuation exactly once).
                let seconds = timeout.seconds
                DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                    state.timeout { box.terminate() }
                }
            }
        } onCancel: {
            box.terminate()
        }
    }
}

/// Holds a `Process` so it can be terminated from the cancellation handler and
/// timeout closure without tripping `Sendable` checks. Termination is the only
/// thing touched across threads, and `Process.terminate()` is safe to call so.
private final class ProcessBox: @unchecked Sendable {
    private let process: Process
    init(_ process: Process) { self.process = process }
    func terminate() { if process.isRunning { process.terminate() } }
}

/// Thread-safe coordinator: stdout EOF, stderr EOF and process exit can land on
/// different queues; the continuation resumes once, when all three are in (or on
/// the first failure/timeout).
private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var stdoutDone = false
    private var stderrDone = false
    private var exitStatus: Int32?
    private var resumed = false
    private let continuation: CheckedContinuation<ProcessResult, Error>

    init(continuation: CheckedContinuation<ProcessResult, Error>) {
        self.continuation = continuation
    }

    func appendStdout(_ data: Data) { lock.withLock { stdout.append(data) } }
    func appendStderr(_ data: Data) { lock.withLock { stderr.append(data) } }
    func markStdoutEOF() { lock.withLock { stdoutDone = true }; tryFinish() }
    func markStderrEOF() { lock.withLock { stderrDone = true }; tryFinish() }
    func markExited(status: Int32) { lock.withLock { exitStatus = status }; tryFinish() }

    private func tryFinish() {
        lock.lock()
        guard !resumed, stdoutDone, stderrDone, let status = exitStatus else { lock.unlock(); return }
        resumed = true
        let result = ProcessResult(exitCode: status, stdout: stdout, stderr: stderr)
        lock.unlock()
        continuation.resume(returning: result)
    }

    func fail(_ error: ProcessRunnerError) {
        lock.lock()
        guard !resumed else { lock.unlock(); return }
        resumed = true
        lock.unlock()
        continuation.resume(throwing: error)
    }

    /// Resume with a timeout error, running `terminate` first to kill the child.
    func timeout(_ terminate: () -> Void) {
        lock.lock()
        guard !resumed else { lock.unlock(); return }
        resumed = true
        lock.unlock()
        terminate()
        continuation.resume(throwing: ProcessRunnerError.timedOut)
    }
}

private extension Duration {
    /// Whole + fractional seconds as a `Double`.
    var seconds: Double {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
