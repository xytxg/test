import Foundation
import AVFoundation
import UniformTypeIdentifiers

struct MediaSource: Identifiable, Decodable {
    var id: String
    var name: String
    var url: String
    var mime: String?
    var headers: [String: String]?
    var cenc: CENCPlan?
}
struct CENCPlan: Decodable {
    struct Segment: Decodable { var start: Int64; var size: Int64; var data: String?; var remote: Int64? }
    struct Sample: Decodable { var offset: Int64; var size: Int64; var iv: String }
    var key: String
    var total: Int64
    var size: Int64
    var segments: [Segment]
    var samples: [Sample]
    var validator: String?
    func validate() throws {
        guard size > 0, size <= 1_100_000_000, total > 0, total <= 1_073_741_824,
              (try? SourceCrypto.decode(key, "hex").count) == 16,
              segments.count <= 128, samples.count <= 100000 else { throw WeBoxError("媒体计划超出范围") }
        var position: Int64 = 0
        for segment in segments {
            guard segment.start == position, segment.size > 0, segment.size <= size - position else { throw WeBoxError("媒体分段不连续") }
            if let inline = segment.data {
                guard segment.remote == nil, segment.size <= 4_194_304,
                      Data(base64Encoded: inline)?.count == Int(segment.size) else { throw WeBoxError("媒体索引无效") }
            } else {
                guard let remote = segment.remote, remote >= 0, remote <= total,
                      segment.size <= total - remote else { throw WeBoxError("远程媒体分段无效") }
            }
            position += segment.size
        }
        guard position == size else { throw WeBoxError("媒体总长度不匹配") }
        var end: Int64 = 0
        for sample in samples {
            guard sample.offset >= end, sample.size > 0, sample.size <= 16_777_216,
                  sample.offset <= total, sample.size <= total - sample.offset,
                  Data(base64Encoded: sample.iv)?.count == 8 else { throw WeBoxError("CENC 样本无效") }
            end = sample.offset + sample.size
        }
    }
}

// The source supplies a clear moov and a bounded sample map. AVFoundation asks
// for virtual ranges; only the requested remote bytes and intersecting samples
// are fetched. No localhost server or full-file decryption is required.
final class MediaLoader: NSObject, AVAssetResourceLoaderDelegate {
    let source: MediaSource
    let plan: CENCPlan
    private let key: Data
    private let session: URLSession
    private let queue = DispatchQueue(label: "com.xylyra.webox.media")
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private let cache = NSCache<NSNumber, NSData>()
    init(source: MediaSource, session: URLSession? = nil) throws {
        guard let plan = source.cenc, let url = URL(string: source.url), url.scheme == "https", url.host != nil else { throw WeBoxError("加密媒体地址无效") }
        try plan.validate()
        self.source = source; self.plan = plan; self.key = try SourceCrypto.decode(plan.key, "hex")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 40
        config.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: config)
        cache.totalCostLimit = 24 * 1024 * 1024
        super.init()
    }
    func asset() -> AVURLAsset {
        let asset = AVURLAsset(url: URL(string: "webox-media://local/\(UUID().uuidString).mp4")!)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }
    func stop() {
        queue.async { [self] in for task in tasks.values { task.cancel() }; tasks.removeAll(); cache.removeAllObjects() }
        session.invalidateAndCancel()
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        let info = loadingRequest.contentInformationRequest
        info?.contentType = UTType.mpeg4Movie.identifier
        info?.contentLength = plan.size
        info?.isByteRangeAccessSupported = true
        guard let dataRequest = loadingRequest.dataRequest else { loadingRequest.finishLoading(); return true }
        let start = max(dataRequest.requestedOffset, dataRequest.currentOffset)
        guard start >= 0, start < plan.size, dataRequest.requestedLength >= 0 else {
            loadingRequest.finishLoading(with: WeBoxError("播放请求区间无效")); return true
        }
        let requestedEnd = dataRequest.requestsAllDataToEndOfResource ? plan.size : min(plan.size, dataRequest.requestedOffset + Int64(dataRequest.requestedLength))
        let identity = ObjectIdentifier(loadingRequest)
        tasks[identity] = Task { [self] in
            do {
                var offset = start
                while offset < requestedEnd {
                    try Task.checkCancellation()
                    let end = min(offset + 524288, requestedEnd)
                    let data = try await bytes(offset..<end)
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        queue.async {
                            if !loadingRequest.isCancelled { dataRequest.respond(with: data) }
                            continuation.resume()
                        }
                    }
                    offset = end
                }
                queue.async { [self] in
                    tasks.removeValue(forKey: identity)
                    if !loadingRequest.isCancelled { loadingRequest.finishLoading() }
                }
            } catch {
                queue.async { [self] in
                    tasks.removeValue(forKey: identity)
                    if !loadingRequest.isCancelled { loadingRequest.finishLoading(with: error) }
                }
            }
        }
        return true
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        tasks.removeValue(forKey: ObjectIdentifier(loadingRequest))?.cancel()
    }
    func bytes(_ range: Range<Int64>) async throws -> Data {
        var output = Data()
        for segment in plan.segments {
            let lower = max(range.lowerBound, segment.start), upper = min(range.upperBound, segment.start + segment.size)
            guard lower < upper else { continue }
            let localStart = lower - segment.start
            if let inline = segment.data, let data = Data(base64Encoded: inline) {
                output.append(data.subdata(in: Int(localStart)..<Int(localStart + upper - lower)))
            } else if let remote = segment.remote {
                let remoteRange = (remote + localStart)..<(remote + localStart + upper - lower)
                var data = try await fetch(remoteRange)
                for (index, sample) in plan.samples.enumerated() {
                    if sample.offset >= remoteRange.upperBound { break }
                    let lo = max(sample.offset, remoteRange.lowerBound), hi = min(sample.offset + sample.size, remoteRange.upperBound)
                    if lo >= hi { continue }
                    let decrypted: Data
                    if let cached = cache.object(forKey: NSNumber(value: index)) { decrypted = cached as Data }
                    else {
                        let encrypted = try await fetch(sample.offset..<(sample.offset + sample.size))
                        let iv = Data(base64Encoded: sample.iv)! + Data(repeating: 0, count: 8)
                        decrypted = try SourceCrypto.aes(encrypted, key: key, iv: iv, mode: "CTR", padding: false, decrypt: true)
                        cache.setObject(decrypted as NSData, forKey: NSNumber(value: index), cost: decrypted.count)
                    }
                    data.replaceSubrange(Int(lo - remoteRange.lowerBound)..<Int(hi - remoteRange.lowerBound),
                                         with: decrypted.subdata(in: Int(lo - sample.offset)..<Int(hi - sample.offset)))
                }
                output.append(data)
            }
        }
        guard Int64(output.count) == range.upperBound - range.lowerBound else { throw WeBoxError("媒体区间拼接失败") }
        return output
    }
    private func fetch(_ range: Range<Int64>) async throws -> Data {
        var request = URLRequest(url: URL(string: source.url)!)
        for (key, value) in source.headers ?? [:] { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue("bytes=\(range.lowerBound)-\(range.upperBound - 1)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if let validator = plan.validator { request.setValue(validator, forHTTPHeaderField: "If-Range") }
        let (stream, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 206, http.url?.scheme == "https",
              http.value(forHTTPHeaderField: "Content-Range") == "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(plan.total)" else {
            throw WeBoxError("媒体服务器未返回正确的 Range，或地址已过期")
        }
        if let validator = plan.validator {
            let etag = http.value(forHTTPHeaderField: "ETag")
            let modified = http.value(forHTTPHeaderField: "Last-Modified")
            let actual = etag?.hasPrefix("W/") == true ? modified : (etag ?? modified)
            if let actual, actual != validator { throw WeBoxError("媒体内容已变化，请重新播放") }
        }
        var data = Data()
        for try await byte in stream {
            if Int64(data.count) >= range.upperBound - range.lowerBound { throw WeBoxError("媒体区间过大") }; data.append(byte)
        }
        guard Int64(data.count) == range.upperBound - range.lowerBound else { throw WeBoxError("媒体区间不完整") }
        return data
    }
}
