import Foundation
import CommonCrypto
import Security
import zlib

enum SDKCrypto {
    static func call(_ method: String, _ p: [String: Any]) throws -> Any {
        let text = p["text"] as? String ?? ""
        switch method {
        case "crypto.random": return try SourceCrypto.invoke(["method":"random", "args":[p["size"] as? Int ?? 0]])
        case "crypto.hash":
            var options = p; options["outputEncoding"] = p["outputEncoding"] ?? "hex"
            return try SourceCrypto.invoke(["method":"hash", "args":[p["algorithm"] as? String ?? "sha256", text, options]])
        case "crypto.gzip": return try SourceCrypto.invoke(["method":"gzip", "args":[text, p]])
        case "crypto.aes": return try SourceCrypto.invoke(["method":p["decrypt"] as? Bool == true ? "aesDecrypt" : "aesEncrypt", "args":[text, p["key"] as? String ?? "", p["iv"] as? String ?? "", p]])
        case "crypto.encode": return try SourceCrypto.encode(SourceCrypto.decode(text, p["from"] as? String ?? "utf8"), p["to"] as? String ?? "base64")
        case "crypto.hmac":
            let name = (p["algorithm"] as? String ?? "sha256").lowercased().replacingOccurrences(of: "-", with: "")
            let algorithms: [String:(CCHmacAlgorithm,Int)] = ["md5":(CCHmacAlgorithm(kCCHmacAlgMD5),16),"sha1":(CCHmacAlgorithm(kCCHmacAlgSHA1),20),"sha224":(CCHmacAlgorithm(kCCHmacAlgSHA224),28),"sha256":(CCHmacAlgorithm(kCCHmacAlgSHA256),32),"sha384":(CCHmacAlgorithm(kCCHmacAlgSHA384),48),"sha512":(CCHmacAlgorithm(kCCHmacAlgSHA512),64)]
            guard let (algorithm,length) = algorithms[name] else { throw WeBoxError("未支持的 HMAC 算法") }
            let key = try SourceCrypto.decode(p["key"] as? String ?? "", p["keyEncoding"] as? String ?? "utf8")
            let data = try SourceCrypto.decode(text, p["inputEncoding"] as? String ?? "utf8")
            var output = [UInt8](repeating: 0, count: length)
            key.withUnsafeBytes { k in data.withUnsafeBytes { d in CCHmac(algorithm,k.baseAddress,key.count,d.baseAddress,data.count,&output) } }
            return try SourceCrypto.encode(Data(output), p["outputEncoding"] as? String ?? "hex")
        case "crypto.rsa": return try rsa(text, key: p["key"] as? String ?? "", decrypt: p["decrypt"] as? Bool == true)
        case "code.decode":
            let raw = try SourceCrypto.decode(p["codeBase64"] as? String ?? "", "base64")
            let data = p["compression"] as? String == "gzip" ? try gunzip(raw) : raw
            guard data.count <= 524288, let value = String(data: data, encoding: .utf8) else { throw WeBoxError("DOM 脚本编码无效或过大") }; return value
        default: throw WeBoxError("未支持的加密方法：" + method)
        }
    }
    static func gunzip(_ input: Data) throws -> Data {
        var stream = z_stream()
        guard inflateInit2_(&stream, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw WeBoxError("解压初始化失败") }
        defer { inflateEnd(&stream) }
        var output = Data()
        try input.withUnsafeBytes { bytes in
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: bytes.bindMemory(to: Bytef.self).baseAddress); stream.avail_in = uInt(input.count)
            var status = Z_OK
            repeat {
                var block = [UInt8](repeating: 0, count: 32768)
                status = block.withUnsafeMutableBytes { destination in
                    stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress; stream.avail_out = uInt(destination.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                guard status == Z_OK || status == Z_STREAM_END else { throw WeBoxError("压缩脚本无效") }
                output.append(contentsOf: block.prefix(32768 - Int(stream.avail_out)))
                guard output.count <= 524288 else { throw WeBoxError("解压脚本过大") }
            } while status != Z_STREAM_END
        }; return output
    }
    private static func rsa(_ text: String, key pem: String, decrypt: Bool) throws -> String {
        let lines = pem.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("-----") }.joined()
        guard var data = Data(base64Encoded: lines), data.count <= 16384 else { throw WeBoxError("RSA 密钥编码无效") }
        // SecKey expects PKCS#1. Unwrap PKCS#8 / SubjectPublicKeyInfo when present.
        if pem.contains("BEGIN PUBLIC KEY") || pem.contains("BEGIN PRIVATE KEY") {
            let sequence = try children(data)
            if decrypt { guard sequence.count >= 3 else { throw WeBoxError("PKCS#8 密钥无效") }; data = sequence[2].value }
            else { guard sequence.count >= 2, sequence[1].value.first == 0 else { throw WeBoxError("SPKI 密钥无效") }; data = sequence[1].value.dropFirst() }
        }
        var error: Unmanaged<CFError>?
        let attributes: [String:Any] = [kSecAttrKeyType as String:kSecAttrKeyTypeRSA,kSecAttrKeyClass as String:decrypt ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(data as CFData, attributes as CFDictionary, &error) else { throw WeBoxError("无法读取 RSA 密钥") }
        let input = decrypt ? try SourceCrypto.decode(text, "base64") : Data(text.utf8)
        let result = decrypt ? SecKeyCreateDecryptedData(key, .rsaEncryptionPKCS1, input as CFData, &error) : SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, input as CFData, &error)
        guard let result else { throw WeBoxError("RSA 处理失败") }
        return decrypt ? try SourceCrypto.encode(result as Data, "utf8") : (result as Data).base64EncodedString()
    }
    private static func children(_ data: Data) throws -> [(tag: UInt8, value: Data)] {
        let bytes = [UInt8](data); var index = 0
        func read() throws -> (UInt8,Data) {
            guard index + 2 <= bytes.count else { throw WeBoxError("ASN.1 数据不完整") }
            let tag=bytes[index]; index+=1; var count=Int(bytes[index]);index+=1
            if count & 0x80 != 0 { let n=count & 0x7f;guard n>0,n<=4,index+n<=bytes.count else { throw WeBoxError("ASN.1 长度无效") };count=0;for _ in 0..<n {count=(count<<8)|Int(bytes[index]);index+=1} }
            guard count <= bytes.count-index else { throw WeBoxError("ASN.1 数据截断") }
            let value=Data(bytes[index..<index+count]);index+=count;return(tag,value)
        }
        let root=try read();guard root.0==0x30 else { throw WeBoxError("RSA 密钥结构无效") }
        let inner=[UInt8](root.1); var cursor=0;var result:[(UInt8,Data)]=[]
        while cursor<inner.count {
            guard cursor+2<=inner.count else { throw WeBoxError("密钥不完整") };let tag=inner[cursor];cursor+=1;var size=Int(inner[cursor]);cursor+=1
            if size&0x80 != 0 {let n=size&0x7f;guard n>0,n<=4,cursor+n<=inner.count else {throw WeBoxError("密钥长度无效")};size=0;for _ in 0..<n{size=(size<<8)|Int(inner[cursor]);cursor+=1}}
            guard size<=inner.count-cursor else {throw WeBoxError("密钥截断")};result.append((tag,Data(inner[cursor..<cursor+size])));cursor+=size
        };return result
    }
}
