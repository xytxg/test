import Foundation
import CommonCrypto
import Security
import zlib

struct WeBoxError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

enum SourceCrypto {
    static func decode(_ value: String, _ encoding: String = "utf8") throws -> Data {
        switch encoding.lowercased() {
        case "base64":
            guard let data = Data(base64Encoded: value) else { throw WeBoxError("Base64 数据无效") }; return data
        case "hex":
            guard value.count % 2 == 0 else { throw WeBoxError("Hex 数据无效") }
            var result = Data(); var i = value.startIndex
            while i < value.endIndex {
                let end = value.index(i, offsetBy: 2)
                guard let byte = UInt8(value[i..<end], radix: 16) else { throw WeBoxError("Hex 数据无效") }
                result.append(byte); i = end
            }; return result
        case "utf8", "utf-8": return Data(value.utf8)
        default: throw WeBoxError("不支持的字符编码：\(encoding)")
        }
    }
    static func encode(_ data: Data, _ encoding: String) throws -> String {
        switch encoding.lowercased() {
        case "hex": return data.map { String(format: "%02x", $0) }.joined()
        case "base64": return data.base64EncodedString()
        case "utf8", "utf-8":
            guard let s = String(data: data, encoding: .utf8) else { throw WeBoxError("UTF-8 数据无效") }; return s
        default: throw WeBoxError("不支持的字符编码")
        }
    }
    static func hash(_ algorithm: String, _ data: Data) throws -> Data {
        let lengths = ["md5":16, "sha1":20, "sha256":32, "sha384":48, "sha512":64]
        let name = algorithm.lowercased().replacingOccurrences(of: "-", with: "")
        guard let length = lengths[name] else { throw WeBoxError("不支持的哈希：\(algorithm)") }
        var result = [UInt8](repeating: 0, count: length)
        data.withUnsafeBytes { bytes in
            switch name {
            case "md5": _ = CC_MD5(bytes.baseAddress, CC_LONG(data.count), &result)
            case "sha1": _ = CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &result)
            case "sha256": _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &result)
            case "sha384": _ = CC_SHA384(bytes.baseAddress, CC_LONG(data.count), &result)
            default: _ = CC_SHA512(bytes.baseAddress, CC_LONG(data.count), &result)
            }
        }; return Data(result)
    }
    static func aes(_ data: Data, key: Data, iv: Data, mode: String, padding: Bool, decrypt: Bool) throws -> Data {
        guard [16,24,32].contains(key.count), mode == "ECB" || iv.count == 16,
              ["CBC", "ECB", "CTR"].contains(mode) else { throw WeBoxError("AES 参数无效") }
        var cryptor: CCCryptorRef?
        let status = key.withUnsafeBytes { k in iv.withUnsafeBytes { v in
            CCCryptorCreateWithMode(CCOperation(decrypt ? kCCDecrypt : kCCEncrypt),
                CCMode(mode == "CTR" ? kCCModeCTR : mode == "ECB" ? kCCModeECB : kCCModeCBC),
                CCAlgorithm(kCCAlgorithmAES), CCPadding(padding ? ccPKCS7Padding : ccNoPadding),
                v.baseAddress, k.baseAddress, key.count, nil, 0, 0,
                CCModeOptions(mode == "CTR" ? kCCModeOptionCTR_BE : 0), &cryptor)
        }}
        guard status == kCCSuccess, let cryptor else { throw WeBoxError("AES 初始化失败：\(status)") }
        defer { CCCryptorRelease(cryptor) }
        var output = Data(count: data.count + 32); let capacity = output.count
        var moved = 0, final = 0
        let update = output.withUnsafeMutableBytes { out in data.withUnsafeBytes { input in
            CCCryptorUpdate(cryptor, input.baseAddress, data.count, out.baseAddress, capacity, &moved)
        }}
        guard update == kCCSuccess else { throw WeBoxError("AES 处理失败：\(update)") }
        let finish = output.withUnsafeMutableBytes { out in
            CCCryptorFinal(cryptor, out.baseAddress?.advanced(by: moved), capacity - moved, &final)
        }
        guard finish == kCCSuccess else { throw WeBoxError("AES 填充无效：\(finish)") }
        output.count = moved + final; return output
    }
    static func gzip(_ data: Data) throws -> Data {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY,
                           ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw WeBoxError("gzip 初始化失败") }
        defer { deflateEnd(&stream) }
        var result = Data()
        try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(data.count)
            var status: Int32 = Z_OK
            repeat {
                var block = [UInt8](repeating: 0, count: 32768)
                status = block.withUnsafeMutableBytes { out in
                    stream.next_out = out.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(out.count)
                    return deflate(&stream, Z_FINISH)
                }
                guard status == Z_OK || status == Z_STREAM_END else { throw WeBoxError("gzip 压缩失败") }
                result.append(contentsOf: block.prefix(32768 - Int(stream.avail_out)))
            } while status != Z_STREAM_END
        }; return result
    }
    static func invoke(_ request: [String: Any]) throws -> Any {
        let method = request["method"] as? String ?? ""
        let args = request["args"] as? [Any] ?? []
        func str(_ i: Int) -> String { i < args.count ? args[i] as? String ?? "" : "" }
        let options = args.last as? [String: Any] ?? [:]
        func opt(_ key: String, _ fallback: String) -> String { options[key] as? String ?? fallback }
        if method == "random" {
            let count = args.first as? Int ?? 0
            guard (0...65536).contains(count) else { throw WeBoxError("随机数据过大") }
            var bytes = [UInt8](repeating: 0, count: count)
            guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw WeBoxError("随机数失败") }
            return bytes.map(Int.init)
        }
        let output = opt("outputEncoding", "base64")
        switch method {
        case "hash": return try encode(hash(str(0), decode(str(1), opt("inputEncoding", "utf8"))), output)
        case "gzip": return try encode(gzip(decode(str(0), opt("inputEncoding", "utf8"))), output)
        case "aesEncrypt", "aesDecrypt":
            let data = try decode(str(0), opt("inputEncoding", "utf8"))
            let key = try decode(str(1), opt("keyEncoding", "utf8"))
            let iv = try decode(str(2), opt("ivEncoding", "utf8"))
            return try encode(aes(data, key: key, iv: iv, mode: opt("mode", "CBC").uppercased(),
                                  padding: opt("padding", "Pkcs7").lowercased() != "nopadding", decrypt: method == "aesDecrypt"), output)
        default: throw WeBoxError("不支持的加密接口：\(method)")
        }
    }
}
