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

    var routeName: String { isSOCKS ? "手动 SOCKS5" : "手动 HTTP CONNECT" }

    func diagnose(target: URL) async -> String {
        guard !isSOCKS, let host = target.host, !host.contains("\r"), !host.contains("\n") else {
            return "当前线路为手动 SOCKS5。请核对地址和端口。"
        }
        let authority = host + ":" + String(target.port ?? 443)
        let request = Data("CONNECT \(authority) HTTP/1.1\r\nHost: \(authority)\r\nConnection: close\r\n\r\n".utf8)
        do {
            let response = try await NetworkRouteProbe(endpoint: endpoint, framing: .line).exchange(request)
            let parts = String(decoding: response, as: UTF8.self).split(separator: " ")
            guard parts.count >= 2, ["HTTP/1.0", "HTTP/1.1"].contains(parts[0]),
                  let status = Int(parts[1]), (100...599).contains(status) else {
                return "代理端口可达，但没有返回有效的 HTTP CONNECT 状态。"
            }
            switch status {
            case 200: return "代理接受 CONNECT（200），失败发生在后续的 HTTPS 请求。"
            case 407: return "代理要求认证（CONNECT 407）。请检查代理服务的认证设置。"
            default: return "代理拒绝 CONNECT（HTTP \(status)）。"
            }
        } catch let error as NWError {
            if case .posix(let code) = error {
                return "代理连接失败（系统错误 \(code.rawValue)）。请核对代理端口是否正在监听。"
            }
            return "无法连接到所填的代理。"
        } catch let error as URLError where error.code == .timedOut {
            return "代理 CONNECT 探测超时。请检查代理端口和代理自身的出站线路。"
        } catch {
            return "未完成代理 CONNECT 探测。"
        }
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
