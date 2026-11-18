import Foundation
import Network

enum SurgeVIFDNS {
    // Documented iOS VIF DNS endpoint. Do not discover or use it implicitly.
    private static let surgeEndpoint: NWEndpoint = .hostPort(host: "198.18.0.4", port: 53)

    static func resolve(_ host: String) async throws -> [NWEndpoint.Host] {
        try await resolve(host, using: surgeEndpoint)
    }

    static func resolve(_ host: String, using endpoint: NWEndpoint) async throws -> [NWEndpoint.Host] {
        let request = try query(host, id: UInt16.random(in: 0...UInt16.max))
        let probe = NetworkRouteProbe(endpoint: endpoint, framing: .datagram)
        let response = try await probe.exchange(request)
        let addresses = virtualAddresses(response, matching: request)
        guard !addresses.isEmpty else {
            throw WeBoxError("Surge 未返回虚拟地址。请确认 Surge VPN 已启动并接管 DNS。")
        }
        return addresses
    }

    static func query(_ host: String, id: UInt16) throws -> Data {
        let name = host.lowercased()
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        guard name.utf8.count <= 253, labels.count > 1,
              labels.allSatisfy({ (1...63).contains($0.utf8.count) && $0.unicodeScalars.allSatisfy(allowed.contains) }) else {
            throw WeBoxError("Surge 接管线路只支持标准域名")
        }
        var bytes: [UInt8] = [UInt8(id >> 8), UInt8(truncatingIfNeeded: id), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0]
        for label in labels {
            bytes.append(UInt8(label.utf8.count))
            bytes.append(contentsOf: label.utf8)
        }
        bytes.append(contentsOf: [0, 0, 1, 0, 1])
        return Data(bytes)
    }

    static func virtualAddresses(_ packet: Data, matching request: Data) -> [NWEndpoint.Host] {
        let message = Array(packet)
        let original = Array(request)
        guard message.count >= original.count, original.count > 12,
              message[0] == original[0], message[1] == original[1], message[2] & 0xfa == 0x80,
              message[3] & 0x0f == 0, message[4] == 0, message[5] == 1,
              message[12..<original.count].elementsEqual(original[12...]) else { return [] }
        let count = Int(message[6]) * 256 + Int(message[7])
        var cursor = original.count
        var result: [NWEndpoint.Host] = []
        for _ in 0..<count {
            guard skipName(message, cursor: &cursor), cursor + 10 <= message.count else { return [] }
            let isIPv4 = message[cursor] == 0 && message[cursor + 1] == 1 &&
                message[cursor + 2] == 0 && message[cursor + 3] == 1
            let length = Int(message[cursor + 8]) * 256 + Int(message[cursor + 9])
            cursor += 10
            guard cursor + length <= message.count else { return [] }
            if isIPv4, length == 4 {
                let ip = Array(message[cursor..<cursor + 4])
                // Surge's documented IPv4 pool: 198.18.1.1–198.19.255.254.
                let low = ip[1] == 18 && (ip[2] > 1 || ip[2] == 1 && ip[3] >= 1)
                let high = ip[1] == 19 && !(ip[2] == 255 && ip[3] == 255)
                if ip[0] == 198, low || high {
                    let address = NWEndpoint.Host(ip.map(String.init).joined(separator: "."))
                    if !result.contains(address) { result.append(address) }
                    if result.count == 4 { return result }
                }
            }
            cursor += length
        }
        return result
    }

    private static func skipName(_ message: [UInt8], cursor: inout Int) -> Bool {
        while cursor < message.count {
            let size = Int(message[cursor])
            cursor += 1
            if size == 0 { return true }
            if size & 0xc0 == 0xc0 {
                guard cursor < message.count, ((size & 0x3f) << 8) + Int(message[cursor]) < cursor - 1 else { return false }
                cursor += 1
                return true
            }
            guard size <= 63, cursor + size <= message.count else { return false }
            cursor += size
        }
        return false
    }
}
