import Foundation

/// 带进度的文件下载器（URLSessionDownloadDelegate）。
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    static let shared = FileDownloader()

    private let lock = NSLock()
    private var progressHandlers: [Int: @Sendable (Double) -> Void] = [:]
    private var completions: [Int: @Sendable (Result<URL, Error>) -> Void] = [:]
    private var session: URLSession!

    override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func download(
        _ request: URLRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request)
            let identifier = task.taskIdentifier
            lock.lock()
            progressHandlers[identifier] = progress
            completions[identifier] = { result in
                switch result {
                case .success(let url):
                    continuation.resume(returning: url)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            lock.unlock()
            task.resume()
        }
    }

    private func finish(_ task: URLSessionTask, result: Result<URL, Error>) {
        lock.lock()
        let completion = completions.removeValue(forKey: task.taskIdentifier)
        progressHandlers.removeValue(forKey: task.taskIdentifier)
        lock.unlock()
        completion?(result)
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        lock.lock()
        let handler = progressHandlers[downloadTask.taskIdentifier]
        lock.unlock()
        handler?(min(max(fraction, 0), 1))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let ext = downloadTask.originalRequest?.url?.pathExtension ?? "bin"
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext.isEmpty ? "bin" : ext)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            finish(downloadTask, result: .success(destination))
        } catch {
            finish(downloadTask, result: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(task, result: .failure(error))
        }
    }
}
