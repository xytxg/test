import XCTest
import WebKit
import CommonCrypto
@testable import WeBox

final class MockURLProtocol: URLProtocol {
    static var response: ((URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try Self.response!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
final class WeBoxTests: XCTestCase {
    func testHashAndAESKnownVectors() throws {
        XCTAssertEqual(try SourceCrypto.encode(SourceCrypto.hash("sha256", Data("abc".utf8)), "hex"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(try SourceCrypto.encode(SourceCrypto.hash("md5", Data("abc".utf8)), "hex"), "900150983cd24fb0d6963f7d28e17f72")
        let key = try SourceCrypto.decode("2b7e151628aed2a6abf7158809cf4f3c", "hex")
        let iv = try SourceCrypto.decode("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff", "hex")
        let plain = try SourceCrypto.decode("6bc1bee22e409f96e93d7e117393172a", "hex")
        XCTAssertEqual(try SourceCrypto.encode(SourceCrypto.aes(plain, key: key, iv: iv, mode: "CTR", padding: false, decrypt: false), "hex"), "874d6191b620e3261bef6864990db6ce")
        let cbcIV = try SourceCrypto.decode("000102030405060708090a0b0c0d0e0f", "hex")
        XCTAssertEqual(try SourceCrypto.encode(SourceCrypto.aes(plain, key: key, iv: cbcIV, mode: "CBC", padding: false, decrypt: false), "hex"), "7649abac8119b246cee98e9b12e9197d")
        XCTAssertEqual(try SourceCrypto.gzip(Data("hello".utf8)).prefix(2), Data([0x1f,0x8b]))
        XCTAssertThrowsError(try SourceCrypto.decode("0g", "hex"))
    }
    func testCENCRangeReconstructionAndValidation() async throws {
        let key = Data(repeating: 3, count: 16), iv8 = Data(repeating: 2, count: 8)
        let plain = Data((0..<64).map(UInt8.init))
        let encrypted = try SourceCrypto.aes(plain, key: key, iv: iv8 + Data(repeating: 0, count: 8), mode: "CTR", padding: false, decrypt: false)
        let remote = Data(repeating: 0xaa, count: 16) + encrypted
        MockURLProtocol.response = { request in
            let range = request.value(forHTTPHeaderField: "Range")!.dropFirst(6).split(separator: "-").map { Int($0)! }
            return (206, ["Content-Range":"bytes \(range[0])-\(range[1])/80", "ETag":"\"stable\""], remote.subdata(in: range[0]..<(range[1]+1)))
        }
        let plan = CENCPlan(key: try SourceCrypto.encode(key, "hex"), total: 80, size: 84,
                            segments: [.init(start: 0,size: 16,remote: 0),.init(start: 16,size: 4,data: Data([1,2,3,4]).base64EncodedString()),.init(start: 20,size: 64,remote: 16)],
                            samples: [.init(offset: 16,size: 64,iv: iv8.base64EncodedString())],validator: "\"stable\"")
        let source = MediaSource(id: "main",name: "test",url: "https://media.example/movie.mp4",cenc: plan)
        let loader = try MediaLoader(source: source, session: MockURLProtocol.session()); defer { loader.stop() }
        let full = try await loader.bytes(0..<84)
        XCTAssertEqual(full, remote.prefix(16) + Data([1,2,3,4]) + plain)
        let partial = try await loader.bytes(18..<37)
        XCTAssertEqual(partial, Data([3,4]) + plain.prefix(17))
        var invalid = plan; invalid.samples[0].size = 81
        XCTAssertThrowsError(try invalid.validate())
        invalid = plan; invalid.segments[1].start = 17
        XCTAssertThrowsError(try invalid.validate())
        MockURLProtocol.response = { _ in (200, [:], remote) }
        do { _ = try await loader.bytes(0..<16); XCTFail("Expected Range rejection") } catch {}
    }
    @MainActor
    func testProvidedSourceMetadataFiltersSearchAndDetail() async throws {
        let runtime = SourceRuntime(namespace: "tests", session: MockURLProtocol.session()); defer { runtime.close() }
        let sourceURL = try XCTUnwrap(Bundle.main.url(forResource: "hongguo.webox", withExtension: "js"))
        let script = try String(contentsOf: sourceURL, encoding: .utf8)
        let metadata = try await runtime.load(script: script)
        XCTAssertEqual(metadata["id"] as? String, "dev.webox.hongguo")
        let filters = try await runtime.invoke("filters") as? [[String:Any]]
        XCTAssertEqual(filters?.first?["key"] as? String, "category")
        MockURLProtocol.response = { request in
            if request.url!.path.contains("search/result") {
                let json = #"{"searchList":[{"video_data":{"series_id":7470092475068071998,"series_name":"测试短剧","series_cover":"https://p3-novel.byteimg.com/novel-pic/test~x.heic","episode_cnt":24}}],"hasMore":true}"#
                return (200, ["Content-Type":"application/json"], Data(json.utf8))
            }
            let html = #"<script>window._ROUTER_DATA={"loaderData":{"player_(series_id)/page":{"isSuccess":true,"seriesDetail":{"series_id":"7470092475068071998","series_name":"测试短剧","series_intro":"简介","vid_list":["111","222"]}}}}</script>"#
            return (200, ["Content-Type":"text/html"], Data(html.utf8))
        }
        let search = try await runtime.invoke("search", ["query":"测试"]) as! [String:Any]
        let rows = search["items"] as! [[String:Any]]
        XCTAssertEqual(rows.first?["id"] as? String, "7470092475068071998")
        XCTAssertEqual(search["nextCursor"] as? String, "2")
        XCTAssertTrue((rows.first?["poster"] as? String ?? "").hasSuffix(".image"))
        let detail = try await runtime.invoke("detail", ["id":"7470092475068071998"]) as! [String:Any]
        let groups = detail["groups"] as! [[String:Any]]
        XCTAssertEqual((groups[0]["episodes"] as? [[String:Any]])?.count, 2)
        let identity = ["device_id":"1234567890123456", "iid":"2345678901234567", "cdid":"12345678-1234-1234-1234-123456789abc"]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject: identity), forKey: "webox.source.tests.device.v1")
        defer { UserDefaults.standard.removeObject(forKey: "webox.source.tests.device.v1") }
        MockURLProtocol.response = { request in
            XCTAssertTrue(request.value(forHTTPHeaderField: "x-medusa")?.isEmpty == false)
            let json = #"{"code":0,"data":{"cell_view":{"cell_data":[{"video_data":[{"content_type":1,"series_id":"1234","series_name":"目录测试"}]}],"has_more":false}}}"#
            return (200, ["Content-Type":"application/json"], Data(json.utf8))
        }
        let catalog = try await runtime.invoke("list", ["filters":["category":"hot"]]) as! [String:Any]
        XCTAssertEqual((catalog["items"] as? [[String:Any]])?.first?["title"] as? String, "目录测试")
        MockURLProtocol.response = { _ in (200, [:], Data("{}".utf8)) }
        do { _ = try await runtime.invoke("search", ["query":"test"]); XCTFail("Expected source schema error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("结构")) }
    }
    @MainActor
    func testBridgeCryptoPromiseStorageAndBigInt() async throws {
        let runtime = SourceRuntime(namespace: "bridge-tests"); defer { runtime.close() }
        let metadata = try await runtime.load(script: """
        WeBox.define({api:'1.5',id:'test.bridge',name:'Bridge',requires:['crypto'],list:async(ctx)=>{
          await ctx.store.set('test',{value:42}); const saved=await ctx.store.get('test'); await ctx.store.remove('test');
          return {hash:ctx.crypto.hash('sha256','abc',{outputEncoding:'hex'}),random:crypto.getRandomValues(new Uint8Array(16)).length,saved:saved.value,big:String(7470092475068071998n)};
        }});
        """)
        XCTAssertEqual(metadata["name"] as? String, "Bridge")
        let result = try await runtime.invoke("list") as! [String:Any]
        XCTAssertEqual(result["hash"] as? String, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(result["saved"] as? Int, 42)
        XCTAssertEqual(result["random"] as? Int, 16)
        XCTAssertEqual(result["big"] as? String, "7470092475068071998")
    }
}
