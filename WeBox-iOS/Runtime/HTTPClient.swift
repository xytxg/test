import Foundation

struct HTTPResult { let data: Data; let response: HTTPURLResponse }

// One URLSession per client preserves HTTP/2 connections. Responses are accumulated
// in chunks with an enforced bound, rather than one Swift async suspension per byte.
final class HTTPClient: NSObject, @unchecked Sendable {
    private struct Transfer {
        let continuation: CheckedContinuation<HTTPResult, Error>
        let limit: Int
        let httpsOnly: Bool
        var data = Data()
        var response: HTTPURLResponse?
        var failure: Error?
        var redirected = false
    }
    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]
    private var stopped = false
    private var session: URLSession!
    init(configuration: URLSessionConfiguration = .ephemeral) {
        super.init()
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.httpMaximumConnectionsPerHost = 6
        let relay = HTTPDelegate(self)
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: relay, delegateQueue: queue)
    }
    deinit { session.invalidateAndCancel() }
    func close() { lock.lock(); stopped = true; lock.unlock(); session.invalidateAndCancel() }
    func fetch(_ request: URLRequest, limit: Int, httpsOnly: Bool = false, retryDNS: Bool = false) async throws -> HTTPResult {
        do {
            return try await attempt(request, limit: limit, httpsOnly: httpsOnly)
        } catch let failure as HTTPNetworkError where retryDNS && failure.canRetryResolution {
            // DNS failed before headers or body could be sent. Do not replay a
            // request if it reached a server, timed out, or followed a redirect.
            try await Task.sleep(for: .milliseconds(400))
            return try await attempt(request, limit: limit, httpsOnly: httpsOnly)
        }
    }
    private func attempt(_ request: URLRequest, limit: Int, httpsOnly: Bool) async throws -> HTTPResult {
        guard let url = request.url, Self.valid(url, httpsOnly: httpsOnly), limit > 0 else { throw WeBoxError("请求地址或响应上限无效") }
        let cancellation = TransferCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if stopped { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                let task = session.dataTask(with: request)
                transfers[task.taskIdentifier] = Transfer(continuation: continuation, limit: limit, httpsOnly: httpsOnly)
                lock.unlock()
                cancellation.install(task); task.resume()
            }
        } onCancel: { cancellation.cancel() }
    }
    static func valid(_ url: URL, httpsOnly: Bool) -> Bool {
        url.host != nil && url.user == nil && url.password == nil && (url.scheme == "https" || !httpsOnly && url.scheme == "http")
    }
    fileprivate func response(_ task: URLSessionDataTask, _ response: URLResponse, _ completion: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        guard var transfer = transfers[task.taskIdentifier] else { lock.unlock(); completion(.cancel); return }
        if let http = response as? HTTPURLResponse, let url = http.url, Self.valid(url, httpsOnly: transfer.httpsOnly) {
            transfer.response = http
            if response.expectedContentLength > transfer.limit { transfer.failure = WeBoxError("响应超过 \(transfer.limit / 1024) KiB 上限") }
        } else { transfer.failure = WeBoxError("无效的 HTTP 响应") }
        transfers[task.taskIdentifier] = transfer
        let failed = transfer.failure != nil; lock.unlock()
        completion(failed ? .cancel : .allow)
    }
    fileprivate func data(_ task: URLSessionDataTask, _ chunk: Data) {
        lock.lock()
        guard var transfer = transfers[task.taskIdentifier] else { lock.unlock(); return }
        if chunk.count > transfer.limit - transfer.data.count { transfer.failure = WeBoxError("响应超过大小上限") }
        else { transfer.data.append(chunk) }
        transfers[task.taskIdentifier] = transfer
        let failed = transfer.failure != nil; lock.unlock()
        if failed { task.cancel() }
    }
    fileprivate func complete(_ task: URLSessionTask, _ error: Error?) {
        lock.lock(); let transfer = transfers.removeValue(forKey: task.taskIdentifier); lock.unlock()
        guard let transfer else { return }
        if let failure = transfer.failure {
            transfer.continuation.resume(throwing: failure)
        } else if let error = error as? URLError, error.code != .cancelled {
            let host = error.failingURL?.host ?? task.currentRequest?.url?.host ?? task.originalRequest?.url?.host
            let cellularDenied = error.code == .dataNotAllowed || error.networkUnavailableReason == .cellular
            let isDNS = error.code == .cannotFindHost || error.code == .dnsLookupFailed
            let canRetry = isDNS && !cellularDenied && !transfer.redirected &&
                transfer.response == nil && task.countOfBytesSent == 0 && host == task.originalRequest?.url?.host
            transfer.continuation.resume(throwing: HTTPNetworkError(
                code: error.code, host: host, cellularDenied: cellularDenied, canRetryResolution: canRetry
            ))
        } else if let error {
            transfer.continuation.resume(throwing: error)
        } else if let response = transfer.response {
            transfer.continuation.resume(returning: HTTPResult(data: transfer.data, response: response))
        } else {
            transfer.continuation.resume(throwing: WeBoxError("服务器没有返回响应"))
        }
    }
    fileprivate func redirect(_ task: URLSessionTask, _ request: URLRequest, _ completion: @escaping (URLRequest?) -> Void) {
        lock.lock()
        let httpsOnly = transfers[task.taskIdentifier]?.httpsOnly ?? true
        transfers[task.taskIdentifier]?.redirected = true
        lock.unlock()
        completion(request.url.flatMap { Self.valid($0, httpsOnly: httpsOnly) ? request : nil })
    }
}
private final class TransferCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false
    func install(_ value: URLSessionTask) { lock.lock(); task = value; let cancel = cancelled; lock.unlock(); if cancel { value.cancel() } }
    func cancel() { lock.lock(); cancelled = true; let value = task; lock.unlock(); value?.cancel() }
}
private final class HTTPDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    weak var owner: HTTPClient?
    init(_ owner: HTTPClient) { self.owner = owner }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) { owner?.response(dataTask, response, completionHandler) ?? completionHandler(.cancel) }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) { owner?.data(dataTask, data) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { owner?.complete(task, error) }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { owner?.redirect(task, request, completionHandler) ?? completionHandler(nil) }
}
