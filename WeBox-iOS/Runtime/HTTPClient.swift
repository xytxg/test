import Foundation

struct HTTPResult {
    let data: Data
    let response: HTTPURLResponse
    var trace: HTTPTrace? = nil
}

struct HTTPTrace {
    var protocolName: String?
    var dns = false
    var connected = false
    var tls = false
    var sent = false
    var received = false
    var proxy = false
    var redirects = 0

    var summary: String {
        let stages = [(dns, "DNS"), (connected, "TCP"), (tls, "TLS"),
                      (sent, "已发送"), (received, "已响应"), (proxy, "代理")]
            .filter { $0.0 }.map { $0.1 }
        return (stages + [protocolName, redirects > 0 ? "重定向 \(redirects) 次" : nil].compactMap { $0 }).joined(separator: " · ")
    }
}

// One URLSession per client preserves HTTP/2 connections. Responses are accumulated
// in chunks with an enforced bound, rather than one Swift async suspension per byte.
final class HTTPClient: NSObject, @unchecked Sendable {
    private struct Transfer {
        let continuation: CheckedContinuation<HTTPResult, Error>
        let limit: Int
        let httpsOnly: Bool
        let followRedirects: Bool
        var data = Data()
        var response: HTTPURLResponse?
        var failure: Error?
        var redirected = false
        var trace: HTTPTrace?
    }
    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]
    private var stopped = false
    private var session: URLSession!
    private let followRedirects: Bool
    init(configuration: URLSessionConfiguration = .ephemeral, followRedirects: Bool = true) {
        self.followRedirects = followRedirects
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
    func fetch(_ request: URLRequest, limit: Int, httpsOnly: Bool = false, followRedirects: Bool = true) async throws -> HTTPResult {
        guard let url = request.url, Self.valid(url, httpsOnly: httpsOnly), limit > 0 else { throw WeBoxError("请求地址或响应上限无效") }
        let cancellation = TransferCancellation()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if stopped { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
                let task = session.dataTask(with: request)
                transfers[task.taskIdentifier] = Transfer(continuation: continuation, limit: limit, httpsOnly: httpsOnly,
                                                             followRedirects: self.followRedirects && followRedirects)
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
            transfer.continuation.resume(throwing: HTTPNetworkError(
                code: error.code, host: host, cellularDenied: cellularDenied,
                canUseAlternateDNS: !cellularDenied && !transfer.redirected && transfer.response == nil &&
                    task.countOfBytesSent == 0 && transfer.trace?.sent != true &&
                    host?.lowercased() == task.originalRequest?.url?.host?.lowercased(),
                trace: transfer.trace
            ))
        } else if let error {
            transfer.continuation.resume(throwing: error)
        } else if let response = transfer.response {
            transfer.continuation.resume(returning: HTTPResult(data: transfer.data, response: response, trace: transfer.trace))
        } else {
            transfer.continuation.resume(throwing: WeBoxError("服务器没有返回响应"))
        }
    }
    fileprivate func redirect(_ task: URLSessionTask, _ request: URLRequest, _ completion: @escaping (URLRequest?) -> Void) {
        lock.lock()
        let transfer = transfers[task.taskIdentifier]
        transfers[task.taskIdentifier]?.redirected = true
        lock.unlock()
        guard let transfer, transfer.followRedirects,
              let url = request.url, Self.valid(url, httpsOnly: transfer.httpsOnly) else { completion(nil); return }
        var next = request
        if let previous = task.currentRequest?.url, previous.host != url.host ||
            previous.scheme != url.scheme || Self.port(previous) != Self.port(url) {
            for header in ["Authorization", "Cookie", "Proxy-Authorization"] {
                next.setValue(nil, forHTTPHeaderField: header)
            }
        }
        completion(next)
    }

    private static func port(_ url: URL) -> Int { url.port ?? (url.scheme == "https" ? 443 : 80) }

    fileprivate func metrics(_ task: URLSessionTask, _ metrics: URLSessionTaskMetrics) {
        let transactions = metrics.transactionMetrics
        var trace = HTTPTrace()
        trace.protocolName = transactions.last?.networkProtocolName
        trace.dns = transactions.contains { $0.domainLookupStartDate != nil }
        trace.connected = transactions.contains { $0.connectEndDate != nil }
        trace.tls = transactions.contains { $0.secureConnectionEndDate != nil }
        trace.sent = transactions.contains { $0.countOfRequestHeaderBytesSent > 0 || $0.countOfRequestBodyBytesSent > 0 }
        trace.received = transactions.contains { $0.responseStartDate != nil }
        trace.proxy = transactions.contains { $0.isProxyConnection }
        trace.redirects = metrics.redirectCount
        lock.lock()
        transfers[task.taskIdentifier]?.trace = trace
        lock.unlock()
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
    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) { owner?.metrics(task, metrics) }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { owner?.complete(task, error) }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { owner?.redirect(task, request, completionHandler) ?? completionHandler(nil) }
}
