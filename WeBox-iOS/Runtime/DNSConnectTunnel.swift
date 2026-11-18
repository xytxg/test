import Foundation
import Network

// A private, single-origin HTTPS tunnel. URLSession still negotiates TLS
// against the original URL, so SNI, certificate validation and HTTP bytes
// are unchanged. This listener never accepts requests for arbitrary hosts.
final class DNSConnectTunnel: @unchecked Sendable {
    private let queue = DispatchQueue(label: "webox.dns-connect")
    private let listener: NWListener
    private let authority: String
    private let port: NWEndpoint.Port
    private let addresses: [NWEndpoint.Host]
    private var downstream: NWConnection?
    private var upstream: NWConnection?
    private var header = Data()
    private var started = false
    private var ready: CheckedContinuation<NWEndpoint, Error>?

    init(host: String, port: UInt16, addresses: [NWEndpoint.Host]) throws {
        guard let port = NWEndpoint.Port(rawValue: port), !addresses.isEmpty else {
            throw WeBoxError("备用连接没有可用地址")
        }
        self.port = port
        self.authority = host.lowercased() + ":" + String(port.rawValue)
        self.addresses = Array(addresses.prefix(4))
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
        downstream = connection
        connection.start(queue: queue)
        readConnect(connection)
        queue.asyncAfter(deadline: .now() + 4) { [weak self, weak connection] in
            guard let self, let connection, self.downstream === connection, self.upstream == nil else { return }
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
                guard parts.count == 3, parts[0] == "CONNECT", parts[1].lowercased() == self.authority,
                      parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0",
                      end.upperBound == self.header.endIndex else {
                    self.closeConnection()
                    return
                }
                self.header.removeAll()
                self.connect(at: 0, from: connection)
            } else if complete {
                self.closeConnection()
            } else {
                self.readConnect(connection)
            }
        }
    }

    private func connect(at index: Int, from downstream: NWConnection) {
        guard self.downstream === downstream else { return }
        guard addresses.indices.contains(index) else {
            downstream.send(content: Data("HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n".utf8),
                            completion: .contentProcessed { [weak self] _ in self?.closeConnection() })
            return
        }
        let peer = NWConnection(host: addresses[index], port: port, using: .tcp)
        upstream = peer
        // Only advance to another address before TCP connects. HTTP and TLS
        // are owned by URLSession and a submitted request is never replayed.
        let next: @Sendable () -> Void = { [weak self, weak peer, weak downstream] in
            guard let self, let peer, let downstream, self.upstream === peer else { return }
            peer.stateUpdateHandler = nil
            peer.cancel()
            self.connect(at: index + 1, from: downstream)
        }
        peer.stateUpdateHandler = { [weak self, weak peer, weak downstream] state in
            guard let self, let peer, let downstream, self.upstream === peer else { return }
            switch state {
            case .ready:
                peer.stateUpdateHandler = nil
                downstream.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8),
                                completion: .contentProcessed { [weak self] error in
                    guard let self, self.upstream === peer else { return }
                    if error != nil { self.closeConnection(); return }
                    self.pump(from: downstream, to: peer)
                    self.pump(from: peer, to: downstream)
                })
            case .failed: next()
            default: break
            }
        }
        queue.asyncAfter(deadline: .now() + 3) {
            if peer.stateUpdateHandler != nil { next() }
        }
        peer.start(queue: queue)
    }

    private func pump(from source: NWConnection, to destination: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] bytes, _, complete, error in
            guard let self, self.downstream != nil else { return }
            if error != nil { self.closeConnection(); return }
            destination.send(content: bytes, contentContext: complete ? .finalMessage : .defaultMessage,
                             isComplete: complete, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error != nil { self.closeConnection() }
                else if !complete { self.pump(from: source, to: destination) }
            })
        }
    }

    private func closeConnection() {
        let incoming = downstream
        let outgoing = upstream
        downstream = nil
        upstream = nil
        incoming?.cancel()
        outgoing?.stateUpdateHandler = nil
        outgoing?.cancel()
    }
}
