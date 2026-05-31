import Foundation

/// Efficient file download with progress, backed by `URLSessionDownloadTask`
/// (the system handles chunking/buffering — far faster than iterating
/// `URLSession.bytes` one byte at a time). Exposes progress as an async stream;
/// the completed file is moved to `destination` before the temp file is reaped.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    enum Event {
        case progress(fraction: Double, received: Int64, total: Int64)
        case finished
    }

    private var continuation: AsyncThrowingStream<Event, Error>.Continuation?
    private var session: URLSession?
    private var destination: URL?

    /// Start downloading `url` to `destination`, yielding progress until done.
    /// Cancelling the consuming task (dropping the iterator) cancels the request.
    func download(from url: URL, to destination: URL) -> AsyncThrowingStream<Event, Error> {
        AsyncThrowingStream { continuation in
            self.continuation = continuation
            self.destination = destination
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.downloadTask(with: url)
            continuation.onTermination = { @Sendable _ in task.cancel() }
            task.resume()
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let fraction = totalBytesExpectedToWrite > 0
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        continuation?.yield(.progress(
            fraction: fraction, received: totalBytesWritten, total: totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file is deleted as soon as this returns, so move it now.
        guard let destination else { return }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.yield(.finished)
            continuation?.finish()
        } catch {
            continuation?.finish(throwing: error)
        }
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error {
            continuation?.finish(throwing: error)
            session.finishTasksAndInvalidate()
        }
    }
}
