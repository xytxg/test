import Foundation
import Network

enum AlternateDNS {
    // Retain the setting for users who enabled encrypted DNS in 0.2.1.
    static let preferenceKey = "webox.encryptedDNS"

    private struct Reply: Decodable {
        struct Record: Decodable { let type: Int; let data: String }
        let Status: Int
        let Answer: [Record]?
    }

    private static let resolvers = [
        "https://dns.alidns.com/resolve",
        "https://cloudflare-dns.com/dns-query",
        "https://1.1.1.1/dns-query"
    ]

    static func resolve(_ host: String) async throws -> [NWEndpoint.Host] {
        let labelCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
        guard host.count <= 253, host.contains("."), host.unicodeScalars.allSatisfy(labelCharacters.contains) else {
            throw WeBoxError("备用 DNS 仅支持公网域名")
        }
        let client = HTTPClient(followRedirects: false)
        defer { client.close() }
        for resolver in resolvers {
            try Task.checkCancellation()
            async let v4 = addresses(host, type: 1, resolver: resolver, client: client)
            async let v6 = addresses(host, type: 28, resolver: resolver, client: client)
            let (ipv4, ipv6) = await (v4, v6)
            // Try both families early. A 5G network can be IPv6-only.
            let ordered = (0..<max(ipv4.count, ipv6.count)).flatMap { i in
                [ipv4.indices.contains(i) ? ipv4[i] : nil,
                 ipv6.indices.contains(i) ? ipv6[i] : nil].compactMap { $0 }
            }
            if !ordered.isEmpty { return Array(ordered.prefix(4)) }
        }
        try Task.checkCancellation()
        throw WeBoxError("备用 DNS 未返回可用地址")
    }

    private static func addresses(_ host: String, type: Int, resolver: String, client: HTTPClient) async -> [NWEndpoint.Host] {
        guard var components = URLComponents(string: resolver) else { return [] }
        components.queryItems = [URLQueryItem(name: "name", value: host), URLQueryItem(name: "type", value: type == 1 ? "A" : "AAAA")]
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue("application/dns-json", forHTTPHeaderField: "Accept")
        guard let result = try? await client.fetch(request, limit: 16_384, httpsOnly: true),
              result.response.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: result.data), reply.Status == 0 else { return [] }
        return (reply.Answer ?? []).filter { $0.type == type }.compactMap { publicAddress($0.data) }
    }

    static func publicAddress(_ literal: String) -> NWEndpoint.Host? {
        if let ip = IPv4Address(literal) {
            let b = Array(ip.rawValue)
            switch (b[0], b[1]) {
            case (0, _), (10, _), (127, _), (100, 64...127), (169, 254), (172, 16...31),
                 (192, 0), (192, 168), (198, 18...19), (224...255, _):
                return nil
            default: return .ipv4(ip)
            }
        }
        if let ip = IPv6Address(literal), ip.rawValue.first.map({ $0 & 0xe0 == 0x20 }) == true {
            return .ipv6(ip)
        }
        return nil
    }

    static func fetch(_ request: URLRequest, limit: Int, addresses: [NWEndpoint.Host]) async throws -> HTTPResult {
        guard let url = request.url, url.scheme == "https", let host = url.host,
              let port = UInt16(exactly: url.port ?? 443) else { throw WeBoxError("备用连接仅支持 HTTPS") }
        let tunnel = try DNSConnectTunnel(host: host, port: port, addresses: addresses)
        defer { tunnel.close() }
        let endpoint = try await tunnel.start()
        try Task.checkCancellation()
        let configuration = URLSessionConfiguration.ephemeral
        var proxy = ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: nil)
        proxy.allowFailover = false
        configuration.proxyConfigurations = [proxy]
        let client = HTTPClient(configuration: configuration, followRedirects: false)
        defer { client.close() }
        return try await client.fetch(request, limit: limit, httpsOnly: true)
    }
}
