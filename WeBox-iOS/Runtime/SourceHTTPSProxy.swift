import Foundation
import Network

struct SourceHTTPSProxy: Equatable {
    static let preferenceKey = "webox.sourceHTTPSProxy"
    let address: String
    private let endpoint: NWEndpoint
    private let isSOCKS: Bool

    init(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), ["http", "socks5"].contains(scheme),
              let host = parts.host, !host.isEmpty, host.utf8.count <= 253,
              let value = parts.port, let rawPort = UInt16(exactly: value), rawPort != 0,
              let port = NWEndpoint.Port(rawValue: rawPort),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else {
            throw WeBoxError("请填写 http://主机:端口 或 socks5://主机:端口，不含账号密码。")
        }
        address = text
        endpoint = .hostPort(host: NWEndpoint.Host(host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))), port: port)
        isSOCKS = scheme == "socks5"
    }

    func makeClient() -> HTTPClient {
        var proxy = isSOCKS
            ? ProxyConfiguration(socksv5Proxy: endpoint)
            : ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: nil)
        proxy.allowFailover = false
        let configuration = URLSessionConfiguration.ephemeral
        configuration.proxyConfigurations = [proxy]
        return HTTPClient(configuration: configuration)
    }
}
