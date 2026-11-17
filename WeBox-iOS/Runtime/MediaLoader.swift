import Foundation
import AVFoundation
import UniformTypeIdentifiers

struct MediaSource: Identifiable, Decodable {
    var id: String
    var name: String
    var url: String?
    var mime: String?
    var headers: [String: String]?
    var cenc: CENCPlan?
    var manifest: String?
    var baseUrl: String?
    var summary: String?
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

// A bounded, connection-reusing block store. Neighbouring encrypted samples use
// the same HTTP ranges; concurrent AVFoundation requests share in-flight work.
actor MediaByteStore {
    private let source: MediaSource
    private let plan: CENCPlan
    private let client: HTTPClient
    private let blockSize: Int64 = 524288
    private var blocks: [Int64: Data] = [:]
    private var order: [Int64] = []
    private var inflight: [Int64: Task<Data, Error>] = [:]
    private var cost = 0
    private var stopped = false
    init(source: MediaSource, plan: CENCPlan, client: HTTPClient) { self.source=source;self.plan=plan;self.client=client }
    func close() { stopped=true;for task in inflight.values{task.cancel()};inflight.removeAll();blocks.removeAll();order.removeAll();client.close() }
    func read(_ range: Range<Int64>) async throws -> Data {
        guard range.lowerBound >= 0, range.upperBound <= plan.total, range.lowerBound < range.upperBound else { throw WeBoxError("媒体远程区间无效") }
        var result=Data();var position=range.lowerBound
        while position < range.upperBound {
            try Task.checkCancellation();guard !stopped else { throw CancellationError() }
            let index=position / blockSize, start=index*blockSize
            let block=try await block(index)
            let end=min(range.upperBound,start+Int64(block.count))
            guard end>position else {throw WeBoxError("媒体分块不完整")}
            result.append(block.subdata(in: Int(position-start)..<Int(end-start)));position=end
        };return result
    }
    private func block(_ index: Int64) async throws -> Data {
        if let data=blocks[index] { touch(index);return data }
        if let pending=inflight[index] { return try await pending.value }
        let source=self.source,plan=self.plan,client=self.client,start=index*blockSize,end=min(plan.total,start+blockSize)
        let task=Task<Data,Error> {
            guard let raw=source.url,let url=URL(string:raw) else {throw WeBoxError("媒体地址无效")}
            var request=URLRequest(url:url);request.cachePolicy = .reloadIgnoringLocalCacheData
            for (key,value) in source.headers ?? [:] {request.setValue(value,forHTTPHeaderField:key)}
            request.setValue("bytes=\(start)-\(end-1)",forHTTPHeaderField:"Range");request.setValue("identity",forHTTPHeaderField:"Accept-Encoding")
            if let validator=plan.validator {request.setValue(validator,forHTTPHeaderField:"If-Range")}
            let result=try await client.fetch(request,limit:Int(end-start),httpsOnly:true),http=result.response
            guard http.statusCode==206,http.value(forHTTPHeaderField:"Content-Range")=="bytes \(start)-\(end-1)/\(plan.total)",result.data.count==Int(end-start) else {throw WeBoxError("媒体 Range 无效或地址过期，请重新解析")}
            if let validator=plan.validator {
                let etag=http.value(forHTTPHeaderField:"ETag"),modified=http.value(forHTTPHeaderField:"Last-Modified")
                let actual=etag?.hasPrefix("W/")==true ? modified : (etag ?? modified)
                if let actual,actual != validator {throw WeBoxError("媒体内容已变化，请重新解析")}
            };return result.data
        }
        inflight[index]=task
        do {
            let data=try await task.value;inflight.removeValue(forKey:index)
            guard !stopped else {throw CancellationError()}
            blocks[index]=data;cost+=data.count;touch(index)
            while cost>24*1024*1024,let old=order.first {order.removeFirst();cost-=blocks.removeValue(forKey:old)?.count ?? 0}
            return data
        } catch {inflight.removeValue(forKey:index);throw error}
    }
    private func touch(_ key: Int64) {order.removeAll{$0==key};order.append(key)}
}

// Request bookkeeping stays on queue; immutable plans, the actor store and
// thread-safe NSCache may be used by concurrent resource requests.
final class MediaLoader: NSObject, AVAssetResourceLoaderDelegate, @unchecked Sendable {
    let source: MediaSource
    let plan: CENCPlan
    private let key: Data
    private let store: MediaByteStore
    private let queue=DispatchQueue(label:"com.xylyra.webox.media")
    private var tasks:[ObjectIdentifier:Task<Void,Never>]=[:]
    private let sampleCache=NSCache<NSNumber,NSData>()
    private let inline:[Int64:Data]
    init(source: MediaSource, client: HTTPClient = HTTPClient()) throws {
        guard let plan=source.cenc,let raw=source.url,let url=URL(string:raw),HTTPClient.valid(url,httpsOnly:true) else {throw WeBoxError("加密媒体地址无效")}
        try plan.validate();self.source=source;self.plan=plan;key=try SourceCrypto.decode(plan.key,"hex")
        store=MediaByteStore(source:source,plan:plan,client:client)
        inline=Dictionary(uniqueKeysWithValues:plan.segments.compactMap { segment in segment.data.flatMap { Data(base64Encoded:$0) }.map{(segment.start,$0)} })
        sampleCache.totalCostLimit=8*1024*1024;super.init()
    }
    func asset() -> AVURLAsset {
        let asset=AVURLAsset(url:URL(string:"webox-media://local/\(UUID().uuidString).mp4")!)
        asset.resourceLoader.setDelegate(self,queue:queue);return asset
    }
    func stop() {queue.async{[self] in for task in tasks.values{task.cancel()};tasks.removeAll();sampleCache.removeAllObjects()};Task{await store.close()} }
    func resourceLoader(_ loader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        request.contentInformationRequest?.contentType=UTType.mpeg4Movie.identifier
        request.contentInformationRequest?.contentLength=plan.size
        request.contentInformationRequest?.isByteRangeAccessSupported=true
        guard let demand=request.dataRequest else {request.finishLoading();return true}
        let start=max(demand.requestedOffset,demand.currentOffset)
        guard start>=0,start<plan.size,demand.requestedLength>=0 else {request.finishLoading(with:WeBoxError("播放区间无效"));return true}
        let end=demand.requestsAllDataToEndOfResource ? plan.size : min(plan.size,demand.requestedOffset+Int64(demand.requestedLength))
        let id=ObjectIdentifier(request)
        tasks[id]=Task{[self] in
            do {
                var position=start
                while position<end {
                    try Task.checkCancellation();let upper=min(position+524288,end),data=try await bytes(position..<upper)
                    await withCheckedContinuation{(continuation:CheckedContinuation<Void,Never>) in queue.async{if !request.isCancelled{demand.respond(with:data)};continuation.resume()} };position=upper
                }
                queue.async{[self] in tasks.removeValue(forKey:id);if !request.isCancelled{request.finishLoading()} }
            }catch{queue.async{[self] in tasks.removeValue(forKey:id);if !request.isCancelled{request.finishLoading(with:error)} }}
        };return true
    }
    func resourceLoader(_ loader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {tasks.removeValue(forKey:ObjectIdentifier(request))?.cancel()}
    func bytes(_ range: Range<Int64>) async throws -> Data {
        guard range.lowerBound>=0,range.upperBound<=plan.size,range.lowerBound<range.upperBound else {throw WeBoxError("播放区间无效")}
        var output=Data()
        for segment in plan.segments {
            let lower=max(range.lowerBound,segment.start),upper=min(range.upperBound,segment.start+segment.size)
            guard lower<upper else {continue};let offset=lower-segment.start
            if let data=inline[segment.start] {output.append(data.subdata(in:Int(offset)..<Int(offset+upper-lower)))}
            else if let remote=segment.remote {
                let requested=(remote+offset)..<(remote+offset+upper-lower)
                var data=try await store.read(requested)
                var index=firstSample(after:requested.lowerBound)
                while index<plan.samples.count {
                    let sample=plan.samples[index];if sample.offset>=requested.upperBound{break}
                    let lo=max(sample.offset,requested.lowerBound),hi=min(sample.offset+sample.size,requested.upperBound)
                    if lo<hi {
                        let decrypted:Data
                        if let cached=sampleCache.object(forKey:NSNumber(value:index)){decrypted=cached as Data}
                        else {
                            let encrypted=try await store.read(sample.offset..<(sample.offset+sample.size))
                            let iv=Data(base64Encoded:sample.iv)!+Data(repeating:0,count:8)
                            decrypted=try SourceCrypto.aes(encrypted,key:key,iv:iv,mode:"CTR",padding:false,decrypt:true)
                            sampleCache.setObject(decrypted as NSData,forKey:NSNumber(value:index),cost:decrypted.count)
                        }
                        data.replaceSubrange(Int(lo-requested.lowerBound)..<Int(hi-requested.lowerBound),with:decrypted.subdata(in:Int(lo-sample.offset)..<Int(hi-sample.offset)))
                    };index+=1
                };output.append(data)
            }
        }
        guard Int64(output.count)==range.upperBound-range.lowerBound else {throw WeBoxError("媒体拼接不完整")};return output
    }
    private func firstSample(after position: Int64) -> Int {
        var low=0,high=plan.samples.count
        while low<high {let middle=(low+high)/2,sample=plan.samples[middle];if sample.offset+sample.size<=position{low=middle+1}else{high=middle}};return low
    }
}
