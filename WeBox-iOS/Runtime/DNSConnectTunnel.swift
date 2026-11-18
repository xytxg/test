import Foundation
import Network

// A private, single-origin HTTPS tunnel. URLSession still negotiates TLS
// against the original URL, so SNI, certificate validation and HTTP bytes
// are unchanged. This listener never accepts requests for arbitrary hosts.
final class DNSConnectTunnel: @unchecked Sendable {
    private let queue = DispatchQueue(label: "webox.dns-connect")
    private let listener: NWListener
    private let authority: String
    private let defaultPortHost: String?
    private let port: NWEndpoint.Port
    private let addresses: [NWEndpoint.Host]
    private var downstream: NWConnection?
    private var upstream: NWConnection?
    private var pendingPeers: [Int: NWConnection] = [:]
    private var failures: [String] = []
    private var attemptCount = 0
    private var receivedTLSBytes = false
    private var phase = "本地握手尚未开始"
    private var header = Data()
    private var started = false
    private var ready: CheckedContinuation<NWEndpoint, Error>?

    init(host: String, port: UInt16, addresses: [NWEndpoint.Host]) throws {
        guard let port = NWEndpoint.Port(rawValue: port), !addresses.isEmpty else {
            throw WeBoxError("备用连接没有可用地址")
        }
        self.port = port
        self.authority = host.lowercased() + ":" + String(port.rawValue)
        self.defaultPortHost = port.rawValue == 443 ? host.lowercased() : nil
        self.addresses = Array(addresses.prefix(8))
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        self.listener = try NWListener(using: parameters)
    }

    func start() async throws -> NWEndpoint {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.ready = continuation
                self.listener.stateUpdateHandler = { [weak self] state in self?.listenerUpdated(state) }
                self.listener.newConnectionHandler = { [weak self] connection in
                    guard let self else { connection.cancel(); return }
                    self.accept(connection)
                }
                self.listener.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self, self.ready != nil else { return }
                    self.finishStart(.failure(WeBoxError("备用连接启动超时")))
                    self.listener.cancel()
                }
            }
        }
    }

    func failureDescription() async -> String {
        await withCheckedContinuation { continuation in
            queue.async {
                let details = Array(Set(self.failures)).sorted().joined(separator: "、")
                let attemptText = self.attemptCount > 0 ? "（尝试 \(self.attemptCount) 个地址）" : ""
                let codeText = details.isEmpty ? "" : "，" + details
                continuation.resume(returning: self.phase + attemptText + codeText)
            }
        }
    }

    func close() {
        queue.async {
            self.finishStart(.failure(CancellationError()))
            self.listener.cancel()
            self.closeConnection()
        }
    }

    private func listenerUpdated(_ state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener.port else { return }
            finishStart(.success(.hostPort(host: "127.0.0.1", port: port)))
        case .failed(let error): finishStart(.failure(error))
        case .cancelled: finishStart(.failure(CancellationError()))
        default: break
        }
    }

    private func finishStart(_ result: Result<NWEndpoint, Error>) {
        let continuation = ready
        ready = nil
        continuation?.resume(with: result)
    }

    private func accept(_ connection: NWConnection) {
        guard !started else { connection.cancel(); return }
        started = true
        phase = "本地代理已连接，等待 CONNECT 握手"
        downstream = connection
        connection.start(queue: queue)
        readConnect(connection)
        queue.asyncAfter(deadline: .now() + 4) { [weak self, weak connection] in
            guard let self, let connection, self.downstream === connection, self.attemptCount == 0 else { return }
            self.closeConnection()
        }
    }

    private func readConnect(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] bytes, _, complete, error in
            guard let self, self.downstream === connection else { return }
            if let bytes { self.header.append(bytes) }
            guard error == nil, self.header.count <= 8192 else { self.closeConnection(); return }
            if let end = self.header.range(of: Data("\r\n\r\n".utf8)) {
                let start = String(decoding: self.header[..<end.lowerBound], as: UTF8.self)
                    .components(separatedBy: "\r\n").first ?? ""
                let parts = start.split(separator: " ")
                guard parts.count == 3, parts[0] == "CONNECT",
                      parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0",
                      end.upperBound == self.header.endIndex else {
                    self.phase = "本地 CONNECT 握手格式未通过"
                    self.closeConnection()
                    return
                }
                let target = parts[1].lowercased()
                guard target == self.authority || target == self.defaultPortHost else {
                    self.phase = "本地 CONNECT 目标与源不匹配"
                    self.closeConnection()
                    return
                }
                self.header.removeAll()
                self.raceConnections(from: connection)
            } else if complete {
                self.closeConnection()
            } else {
                self.readConnect(connection)
            }
        }
    }

    private func raceConnections(from downstream: NWConnection) {
        phase = "地址已解析，正在连接 TCP"
        for index in addresses.indices {
            queue.asyncAfter(deadline: .now() + .milliseconds(index * 250)) { [weak self, weak downstream] in
                guard let self, let downstream, self.downstream === downstream, self.upstream == nil else { return }
                self.dial(index, from: downstream)
            }
        }
    }

    private func dial(_ index: Int, from downstream: NWConnection) {
        let peer = NWConnection(host: addresses[index], port: port, using: .tcp)
        pendingPeers[index] = peer
        attemptCount += 1
        peer.stateUpdateHandler = { [weak self, weak peer, weak downstream] state in
            guard let self, let peer, let downstream, self.pendingPeers[index] === peer else { return }
            switch state {
            case .ready: self.connected(peer, at: index, from: downstream)
            case .failed(let error): self.dialFailed(index, reason: Self.describe(error))
            case .waiting(let error):
                if case .posix(let code) = error, [.ENETUNREACH, .EHOSTUNREACH, .ECONNREFUSED].contains(code) {
                    self.dialFailed(index, reason: Self.describe(error))
                }
            default: break
            }
        }
        queue.asyncAfter(deadline: .now() + 5) { [weak self, weak peer] in
            guard let self, let peer, self.pendingPeers[index] === peer else { return }
            self.dialFailed(index, reason: "TCP 超时")
        }
        peer.start(queue: queue)
    }

    private static func describe(_ error: NWError) -> String {
        if case .posix(let code) = error { return "TCP 系统错误 \(code.rawValue)" }
        return "TCP 连接失败"
    }

    private func dialFailed(_ index: Int, reason: String) {
        if let peer = pendingPeers.removeValue(forKey: index) {
            peer.stateUpdateHandler = nil
            peer.cancel()
        }
        failures.append(reason)
        guard failures.count == addresses.count, let downstream else { return }
        phase = "所有候选地址的 TCP 连接均失败"
        downstream.send(content: Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n".utf8),
                        completion: .contentProcessed { [weak self] _ in self?.closeConnection() })
    }

    private func connected(_ peer: NWConnection, at index: Int, from downstream: NWConnection) {
        pendingPeers.removeValue(forKey: index)
        peer.stateUpdateHandler = nil
        upstream = peer
        phase = "TCP 已连接，等待 HTTPS 握手"
        failures.removeAll()
        cancelPendingPeers()
        downstream.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8),
                        completion: .contentProcessed { [weak self] error in
            guard let self, self.upstream === peer else { return }
            if error != nil { self.closeConnection(); return }
            self.pump(from: downstream, to: peer)
            self.pump(from: peer, to: downstream)
        })
    }

    private func cancelPendingPeers() {
        for peer in pendingPeers.values {
            peer.stateUpdateHandler = nil
            peer.cancel()
        }
        pendingPeers.removeAll()
    }

    private func pump(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] bytes, _, complete, error in
            guard let self, self.downstream != nil else { return }
            if error != nil { self.closeConnection(); return }
            if source === self.upstream, bytes?.isEmpty == false, !self.receivedTLSBytes {
                self.receivedTLSBytes = true
                self.phase = "服务器已返回数据，HTTPS 请求未完成"
            }
            destination.send(content: bytes, contentContext: complete ? .finalMessage : .defaultMessage,
                             isComplete: complete, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil { self.closeConnection() }
                else if !complete { self.pump(from: source, to: destination) }
            })
        }
    }

    private func closeConnection() {
        cancelPendingPeers()
        let incoming = downstream
        let outgoing = upstream
        downstream = nil
        upstream = nil
        incoming?.cancel()
        outgoing?.stateUpdateHandler = nil
        outgoing?.cancel()
    }
}
