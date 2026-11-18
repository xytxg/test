import Foundation
import Network

// One bounded exchange. No script URL path, headers, cookies, or body is sent
// through this utility. Used for DNS and for checking a user-selected proxy.
final class NetworkRouteProbe: @unchecked Sendable {
    enum Framing { case datagram, line }

    private let endpoint: NWEndpoint
    private let framing: Framing
    private let queue = DispatchQueue(label: "webox.route-probe")
    private var connection: NWConnection?
    private var result: CheckedContinuation<Data, Error>?
    private var buffer = Data()
    private var started = false
    private var cancelled = false

    init(endpoint: NWEndpoint, framing: Framing) {
        self.endpoint = endpoint
        self.framing = framing
    }

    func exchange(_ request: Data) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !self.cancelled else { continuation.resume(throwing: CancellationError()); return }
                    self.result = continuation
                    let connection = NWConnection(to: self.endpoint, using: self.framing == .datagram ? .udp : .tcp)
                    self.connection = connection
                    connection.stateUpdateHandler = { [weak self, weak connection] state in
                        guard let self, let connection, self.result != nil else { return }
                        switch state {
                        case .ready where !self.started:
                            self.started = true
                            connection.send(content: request, completion: .contentProcessed { [weak self] error in
                                guard let self, self.result != nil else { return }
                                if let error { self.finish(.failure(error)); return }
                                self.receive(connection)
                            })
                        case .failed(let error):
                            self.finish(.failure(error))
                        case .waiting(let error):
                            if case .posix(let code) = error, [.ECONNREFUSED, .ENETUNREACH, .EHOSTUNREACH].contains(code) {
                                self.finish(.failure(error))
                            }
                        default: break
                        }
                    }
                    connection.start(queue: self.queue)
                    self.queue.asyncAfter(deadline: .now() + 4) { [weak self] in
                        self?.finish(.failure(URLError(.timedOut)))
                    }
                }
            }
        } onCancel: {
            queue.async {
                self.cancelled = true
                self.finish(.failure(CancellationError()))
            }
        }
    }

    private func receive(_ connection: NWConnection) {
        switch framing {
        case .datagram:
            connection.receiveMessage { [weak self] data, _, _, error in
                guard let self else { return }
                if let error { self.finish(.failure(error)); return }
                if let data, data.count <= 4096 { self.finish(.success(data)); return }
                self.finish(.failure(WeBoxError("DNS 响应大小无效")))
            }
        case .line:
            connection.receive(minimumIncompleteLength: 1, maximumLength: 2048) { [weak self] data, _, complete, error in
                guard let self, self.result != nil else { return }
                if let error { self.finish(.failure(error)); return }
                if let data { self.buffer.append(data) }
                if let end = self.buffer.range(of: Data("\r\n".utf8)) {
                    self.finish(.success(Data(self.buffer[..<end.lowerBound])))
                } else if complete || self.buffer.count > 2048 {
                    self.finish(.failure(WeBoxError("代理未返回有效状态行")))
                } else {
                    self.receive(connection)
                }
            }
        }
    }

    private func finish(_ outcome: Result<Data, Error>) {
        guard let result else { return }
        self.result = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        result.resume(with: outcome)
    }
}
