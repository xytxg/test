import Foundation
import Network

enum AppDNS {
    static let preferenceKey = "webox.encryptedDNS"

    @MainActor
    static func apply(encrypted: Bool) {
        let context = NWParameters.PrivacyContext.default
        let resolver: NWParameters.PrivacyContext.ResolverConfiguration? = encrypted
            ? .https(URL(string: "https://dns.google/dns-query")!, serverAddresses: [
                .hostPort(host: "8.8.8.8", port: 443),
                .hostPort(host: "8.8.4.4", port: 443),
                .hostPort(host: "2001:4860:4860::8888", port: 443)
            ])
            : nil
        context.requireEncryptedNameResolution(encrypted, fallbackResolver: resolver)
        context.flushCache()
    }
}

struct HTTPNetworkError: LocalizedError {
    let code: URLError.Code
    let host: String?
    let cellularDenied: Bool
    let canRetryResolution: Bool

    var isResolutionFailure: Bool {
        code == .cannotFindHost || code == .dnsLookupFailed
    }

    var errorDescription: String? {
        let reason: String
        if cellularDenied {
            reason = "无法使用蜂窝数据。请在 iOS 设置中检查 WeBox 的蜂窝数据权限，或连接 Wi‑Fi。"
        } else if isResolutionFailure {
            reason = "域名解析失败。请检查当前网络的 DNS 或代理设置。"
        } else {
            switch code {
            case .notConnectedToInternet: reason = "当前没有可用网络。"
            case .timedOut: reason = "网络请求超时。"
            case .cannotConnectToHost: reason = "无法连接到服务器。"
            case .networkConnectionLost: reason = "网络连接已中断。"
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
                 .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
                reason = "无法建立安全连接，请检查代理证书和设备时间。"
            default: reason = "网络请求失败。"
            }
        }
        return [reason, host.map { "域名：\($0)" }, "网络错误 \(code.rawValue)"]
            .compactMap { $0 }.joined(separator: "\n")
    }
}
