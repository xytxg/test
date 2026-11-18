import Foundation

struct HTTPNetworkError: LocalizedError {
    let code: URLError.Code
    let host: String?
    let cellularDenied: Bool
    var canUseAlternateDNS = false
    var recoveryResult: String? = nil
    var trace: HTTPTrace? = nil

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
            case .badURL: reason = "iOS 未能建立此 URL 请求。请查看请求日志中的线路和代理握手结果。"
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
        return [reason, host.map { "域名：\($0)" }, "网络错误 \(code.rawValue)", recoveryResult]
            .compactMap { $0 }.joined(separator: "\n")
    }
}
