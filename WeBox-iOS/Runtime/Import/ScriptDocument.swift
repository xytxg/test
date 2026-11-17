import Foundation
import CryptoKit

struct ScriptDocument {
    static let limit = 8 * 1024 * 1024
    let text: String
    let fingerprint: String
    init(data: Data) throws {
        guard !data.isEmpty, data.count <= Self.limit else { throw WeBoxError("源文件为空或超过 8 MB") }
        let decoded: String?
        if data.starts(with: [0xff, 0xfe]) { decoded = String(data: data, encoding: .utf16LittleEndian) }
        else if data.starts(with: [0xfe, 0xff]) { decoded = String(data: data, encoding: .utf16BigEndian) }
        else { decoded = String(data: data, encoding: .utf8) }
        guard var value = decoded else { throw WeBoxError("无法识别文件编码，请将 JS 保存为 UTF-8 或 UTF-16") }
        if value.first == "\u{feff}" { value.removeFirst() }
        let start = value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300).lowercased()
        guard !start.hasPrefix("<!doctype html"), !start.hasPrefix("<html") else { throw WeBoxError("下载到的是网页，请使用脚本的 Raw / 原始文件链接") }
        guard !value.contains("\u{0000}") else { throw WeBoxError("文件包含二进制数据，请选择 JavaScript 源文件") }
        text = value
        fingerprint = SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func read(_ url: URL) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true {
                try FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            let coordinator = NSFileCoordinator()
            var coordinatorError: NSError?, result: Result<Data, Error>?
            coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { local in
                result = Result {
                    if let size = try local.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > limit { throw WeBoxError("源文件超过 8 MB") }
                    return try Data(contentsOf: local, options: .mappedIfSafe)
                }
            }
            if let coordinatorError { throw coordinatorError }
            guard let result else { throw WeBoxError("文件提供商尚未提供文件，请先在“文件”App 中下载后再导入") }
            return try result.get()
        }.value
    }
}
