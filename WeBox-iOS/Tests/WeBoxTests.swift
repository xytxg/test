import XCTest
import AVFoundation
import CommonCrypto
import UniformTypeIdentifiers
import Network
@testable import WeBox

final class MockURLProtocol: URLProtocol {
    static var response: ((URLRequest) throws -> (Int,[String:String],Data))?
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){
        do{let(status,headers,data)=try Self.response!(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:"HTTP/1.1",headerFields:headers)!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)
        }catch{client?.urlProtocol(self,didFailWithError:error)}
    }
    override func stopLoading(){}
    static func client()->HTTPClient{let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[MockURLProtocol.self];return HTTPClient(configuration:configuration)}
}
final class WeBoxTests:XCTestCase{
    func fixture(_ name:String,_ ext:String="js")throws->URL{try XCTUnwrap(Bundle(for:Self.self).url(forResource:name,withExtension:ext))}
    func script(_ name:String)throws->String{try String(contentsOf:fixture(name),encoding:.utf8)}
    func testHashAESAndHMACVectors()throws{
        XCTAssertEqual(try SourceCrypto.encode(SourceCrypto.hash("sha256",Data("abc".utf8)),"hex"),"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let key=try SourceCrypto.decode("2b7e151628aed2a6abf7158809cf4f3c","hex"),iv=try SourceCrypto.decode("f0f1f2f3f4f5f6f7f8f9fafbfcfdfeff","hex"),plain=try SourceCrypto.decode("6bc1bee22e409f96e93d7e117393172a","hex")
        XCTAssertEqual(try SourceCrypto.encode(SourceCrypto.aes(plain,key:key,iv:iv,mode:"CTR",padding:false,decrypt:false),"hex"),"874d6191b620e3261bef6864990db6ce")
        XCTAssertEqual(try SDKCrypto.call("crypto.hmac",["algorithm":"sha256","text":"The quick brown fox jumps over the lazy dog","key":"key"]) as? String,"f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
        XCTAssertEqual(try SDKCrypto.call("crypto.encode",["text":"中文","from":"utf8","to":"base64"]) as? String,"5Lit5paH")
        XCTAssertEqual(try SDKCrypto.gunzip(SourceCrypto.gzip(Data("hello".utf8))),Data("hello".utf8))
        XCTAssertThrowsError(try SourceCrypto.decode("0g","hex"))
    }
    func testFileOpenRegistrationUsesSystemJavaScriptType()throws{
        let declarations = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey:"CFBundleDocumentTypes") as? [[String:Any]])
        XCTAssertTrue(declarations.contains{($0["LSItemContentTypes"] as? [String])?.contains(UTType.javaScript.identifier)==true})
    }
    func testFileEncodingsAndDownloadedHTML()throws{
        let source="WeBox.define({name:'中文'});"
        XCTAssertEqual(try ScriptDocument(data:Data([0xef,0xbb,0xbf])+Data(source.utf8)).text,source)
        XCTAssertEqual(try ScriptDocument(data:Data([0xff,0xfe])+source.data(using:.utf16LittleEndian)!).text,source)
        XCTAssertEqual(try ScriptDocument(data:Data([0xfe,0xff])+source.data(using:.utf16BigEndian)!).text,source)
        XCTAssertThrowsError(try ScriptDocument(data:Data("<!doctype html><html>download page</html>".utf8)))
        XCTAssertThrowsError(try ScriptDocument(data:Data(repeating:0,count:ScriptDocument.limit+1)))
    }
    func testEpisodeMatchingAcrossDifferentSources()throws{
        let old=Episode(id:"old-123",name:"第07集")
        let group=EpisodeGroup(id:"line2",name:"备用",episodes:[Episode(id:"new1",name:"EP01"),Episode(id:"new7",name:"EP07")])
        XCTAssertEqual(EpisodeMatcher.match(old,index:0,in:group)?.id,"new7")
        XCTAssertEqual(EpisodeMatcher.match(Episode(id:"unknown",name:"Special"),index:1,in:group)?.id,"new7")
    }
    func testBoundedHTTPResponseAndRedirectPolicy()async throws{
        MockURLProtocol.response={_ in(200,["Content-Length":"100"],Data(repeating:7,count:100))}
        let client=MockURLProtocol.client();defer{client.close()}
        do{_ = try await client.fetch(URLRequest(url:URL(string:"https://example.test/data")!),limit:16);XCTFail("oversized response accepted")}catch{}
        XCTAssertFalse(HTTPClient.valid(URL(string:"file:///private/test")!,httpsOnly:false))
        XCTAssertFalse(HTTPClient.valid(URL(string:"http://example.test")!,httpsOnly:true))
        XCTAssertFalse(HTTPClient.valid(URL(string:"https://user:pass@example.test")!,httpsOnly:false))
    }
    @MainActor func testSourceNetworkFailurePreservesHostAndRedactsRequest() async throws {
        let runtime = SourceRuntime(namespace: "network-recovery", client: MockURLProtocol.client())
        defer { runtime.close() }
        _ = try await runtime.load(script: """
            WeBox.define({api:'1.5',id:'test.network',name:'Network',version:'1.0.0',allowHttp:false,
                filters:async()=>[],list:async ctx=>{
                    const reply=await ctx.http.post('https://source.test/catalog?secret=redact-me',
                        {json:{category:'test'},responseType:'json'});
                    return reply.data;
                },
                detail:async()=>({}),play:async()=>({sources:[]})});
            """)
        var requests = 0
        MockURLProtocol.response = { request in
            requests += 1
            XCTAssertEqual(request.httpMethod, "POST")
            throw URLError(.cannotFindHost)
        }

        do {
            _ = try await runtime.invoke("list", ["filters": [:]])
            XCTFail("Expected DNS failure")
        } catch let error as HTTPNetworkError {
            XCTAssertEqual(error.code, .cannotFindHost)
            XCTAssertEqual(error.host, "source.test")
            XCTAssertTrue(error.canUseAlternateDNS, "An unsent DNS failure should qualify for alternate resolution")
            XCTAssertTrue(error.localizedDescription.contains("域名解析失败"))
            XCTAssertFalse(error.localizedDescription.contains("redact-me"))
        }
        XCTAssertEqual(requests, 1, "Do not silently replay a source POST")
    }
    func testAlternateDNSUsesRealTLSAndPreservesPostBytes() async throws {
        let url = try XCTUnwrap(URL(string: "https://webox-transport.test:8766/register?signature=a%2Bb"))
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.httpBody = Data([0, 0xff, 0x78, 0x2b, 0x3d])
        let result = try await AlternateDNS.fetch(request, limit: 1024, addresses: ["127.0.0.1"])
        XCTAssertEqual(result.response.statusCode, 200)
        XCTAssertEqual(result.response.url?.host, url.host)
        XCTAssertEqual(result.data, request.httpBody)

        XCTAssertNil(AlternateDNS.publicAddress("127.0.0.1"))
        XCTAssertNil(AlternateDNS.publicAddress("192.168.1.1"))
        XCTAssertNil(AlternateDNS.publicAddress("fd00::1"))
        XCTAssertNotNil(AlternateDNS.publicAddress("1.1.1.1"))
        XCTAssertNotNil(AlternateDNS.publicAddress("2606:4700:4700::1111"))
    }
    func testCENCBlockCacheAndCrossSegmentRanges()async throws{
        let key=Data(repeating:3,count:16),iv8=Data(repeating:2,count:8),plain=Data((0..<64).map(UInt8.init))
        let encrypted=try SourceCrypto.aes(plain,key:key,iv:iv8+Data(repeating:0,count:8),mode:"CTR",padding:false,decrypt:false)
        let remote=Data(repeating:0xaa,count:16)+encrypted
        var requests=0
        MockURLProtocol.response={request in
            requests+=1
            let range=request.value(forHTTPHeaderField:"Range")!.dropFirst(6).split(separator:"-").map{Int($0)!}
            return(206,["Content-Range":"bytes \(range[0])-\(range[1])/80","ETag":"\"stable\""],remote.subdata(in:range[0]..<(range[1]+1)))
        }
        let plan=CENCPlan(key:try SourceCrypto.encode(key,"hex"),total:80,size:84,segments:[.init(start:0,size:16,remote:0),.init(start:16,size:4,data:Data([1,2,3,4]).base64EncodedString()),.init(start:20,size:64,remote:16)],samples:[.init(offset:16,size:64,iv:iv8.base64EncodedString())],validator:"\"stable\"")
        let source=MediaSource(id:"main",name:"test",url:"https://media.test/movie.mp4",cenc:plan)
        let loader=try MediaLoader(source:source,client:MockURLProtocol.client());defer{loader.stop()}
        let full=try await loader.bytes(0..<84),partial=try await loader.bytes(18..<37)
        XCTAssertEqual(full,remote.prefix(16)+Data([1,2,3,4])+plain)
        XCTAssertEqual(partial,Data([3,4])+plain.prefix(17))
        XCTAssertEqual(requests,1,"neighbouring ranges and samples should share one HTTP block")
        var invalid=plan;invalid.samples[0].size=81;XCTAssertThrowsError(try invalid.validate())
        MockURLProtocol.response={_ in(200,[:],remote)}
        let bad=try MediaLoader(source:source,client:MockURLProtocol.client());defer{bad.stop()}
        do{_ = try await bad.bytes(0..<16);XCTFail("bad Range accepted")}catch{}
    }
    @MainActor func testOpaquePaginationStateSurvivesRepeatedCalls()async throws{
        let runtime=SourceRuntime(namespace:"paging-tests");defer{runtime.close()}
        _ = try await runtime.load(script:script("paging.webox"));_ = try await runtime.invoke("filters")
        let first=try await runtime.invoke("list",["filters":[:]]) as! [String:Any]
        let second=try await runtime.invoke("list",["filters":[:],"cursor":first["nextCursor"]!]) as! [String:Any]
        XCTAssertEqual((second["items"] as? [[String:Any]])?.first?["id"] as? String,"second")
        XCTAssertTrue(second["nextCursor"] is NSNull)
    }
    @MainActor func testThreeScriptProtocolsShareOneUIContract()async throws{
        for(name,format)in[("01-cinema.webox","webox"),("02-documents.widget","widget"),("03-xptv","xptv")]{
            let runtime=SourceRuntime(namespace:"test-"+format);defer{runtime.close()}
            let meta=try await runtime.load(script:script(name),hint:name)
            XCTAssertEqual(meta["format"] as? String,format)
            let filters=try await runtime.invoke("filters") as! [[String:Any]]
            var selection:[String:String]=[:]
            for filter in filters{selection[filter["key"] as! String]=filter["default"] as? String ?? ""}
            let raw=try await runtime.invoke("list",["filters":selection,"page":1])
            let page=try JSONDecoder().decode(CatalogPage.self,from:JSONSerialization.data(withJSONObject:raw))
            let card=try XCTUnwrap(page.items.first)
            let detailRaw=try await runtime.invoke("detail",["id":card.id,"link":card.link ?? "","title":card.title])
            let detail=try JSONDecoder().decode(ContentDetail.self,from:JSONSerialization.data(withJSONObject:detailRaw))
            if format=="xptv"{XCTAssertEqual(detail.groups.count,2)}
            let group=try XCTUnwrap(detail.groups.first),episode=try XCTUnwrap(group.episodes.first)
            let playRaw=try await runtime.invoke("play",["contentId":card.id,"groupId":group.id,"episodeId":episode.id,"episodeLink":episode.link ?? ""])
            let play=try JSONDecoder().decode(PlayResponse.self,from:JSONSerialization.data(withJSONObject:playRaw))
            XCTAssertFalse(play.sources.isEmpty);XCTAssertTrue(play.sources[0].url?.hasSuffix("sample.mp4")==true)
        }
    }
    @MainActor func testImportsPreserveConfigurationsAndHaveNoBuiltinSource()async throws{
        let suite="webox-tests-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!,folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{defaults.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:folder)}
        let app=AppModel(root:folder,defaults:defaults)
        XCTAssertTrue(app.sources.isEmpty)
        let original=try Data(contentsOf:fixture("01-cinema.webox"))
        let(first,updated)=try await app.install(original,origin:"file.js")
        XCTAssertFalse(updated);try app.saveConfiguration(["region":.string("cn")],source:first)
        let secondScript=String(decoding:original,as:UTF8.self).replacingOccurrences(of:"version:'1.0.0'",with:"version:'1.0.1'")
        let(second,replaced)=try await app.install(Data(secondScript.utf8),origin:"updated.js")
        XCTAssertTrue(replaced);XCTAssertEqual(first.id,second.id);XCTAssertEqual(app.configuration(second)["region"],.string("cn"))
        XCTAssertEqual(app.sources.count,1)
        _ = try await app.install(Data(contentsOf:fixture("02-documents.widget")),origin:"widget.js")
        XCTAssertEqual(app.sources.count,2)
        XCTAssertEqual(app.selectedID,first.id,"adding a source should not silently switch the current source")
    }
    @MainActor func testHTMLCryptoBinaryComputeAndDOMInWebKit()async throws{
        let runtime=SourceRuntime(namespace:"utilities-tests");defer{runtime.close()}
        let code="""
        WeBox.define({api:'1.5',id:'test.utilities',name:'Utilities',version:'1.0.0',requires:['html','crypto','compute','dom','binary'],
        filters:async()=>[],detail:async()=>({}),play:async()=>({sources:[]}),
        list:async(ctx)=>{
          await ctx.store.set('x',{value:42});const saved=await ctx.store.get('x');
          const dom=await ctx.dom.run({code:"parent.postMessage({type:'done',result:{value:document.createElement('canvas').getContext('2d')?1:0}},'*')",messageType:'done',errorType:'failed',timeoutMs:5000});
          const result=await ctx.compute.run({code:'function(input){return {sum:input.a+input.b}}',input:{a:2,b:3},timeoutMs:5000});
          const h=__binaryFromBase64('AQIDBA==');const sliced=ctx.binary.read(ctx.binary.slice(h,1,2),0,2);
          return {items:[{id:'1',title:[ctx.html.load('<b>HTML</b>')('b').text(),saved.value,result.sum,dom.result.value,String(sliced[0])].join('/'),kind:'movie',subtitle:ctx.crypto.hash('sha256','abc',{outputEncoding:'hex'})}],nextCursor:null};
        }});
        """
        _ = try await runtime.load(script:code)
        let result=try await runtime.invoke("list",["filters":[:]]) as! [String:Any]
        let item=(result["items"] as! [[String:Any]])[0]
        XCTAssertEqual(item["title"] as? String,"HTML/42/5/1/2")
        XCTAssertEqual(item["subtitle"] as? String,"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    @MainActor func testAttachedSourceIncludingPlaybackSigningAndMP4Plan()async throws{
        let runtime=SourceRuntime(namespace:"hongguo-tests",client:MockURLProtocol.client());defer{runtime.close()}
        let script=try script("hongguo.webox"),video=try Data(contentsOf:fixture("sample","mp4"))
        let identity=["device_id":"1234567890123456","iid":"2345678901234567","cdid":"12345678-1234-1234-1234-123456789abc"]
        UserDefaults.standard.set(try JSONSerialization.data(withJSONObject:identity),forKey:"webox.source.hongguo-tests.device.v1")
        defer{UserDefaults.standard.removeObject(forKey:"webox.source.hongguo-tests.device.v1")}
        MockURLProtocol.response={request in
            let path=request.url!.path
            if request.url!.host=="test.fqnovelvod.com"{
                let parts=request.value(forHTTPHeaderField:"Range")!.dropFirst(6).split(separator:"-").map{Int($0)!};let end=min(parts[1],video.count-1)
                return(206,["Content-Range":"bytes \(parts[0])-\(end)/\(video.count)","ETag":"\"v1\""],video.subdata(in:parts[0]..<(end+1)))
            }
            let json:String
            if path.contains("search/result"){json = #"{"searchList":[{"video_data":{"series_id":7470092475068071998,"series_name":"测试短剧","episode_cnt":24}}],"hasMore":true}"#}
            else if path.contains("multi_video_model"){
                XCTAssertEqual(request.value(forHTTPHeaderField:"Content-Encoding"),"gzip")
                json = #"{"code":0,"data":{"111":{"video_model":{"video_list":[{"codec_type":"h264","vwidth":960,"vheight":540,"main_url":"https://test.fqnovelvod.com/sample.mp4"}]}}}}"#
            }else if path.contains("bookmall"){
                XCTAssertFalse((request.value(forHTTPHeaderField:"x-medusa") ?? "").isEmpty)
                json = #"{"code":0,"data":{"cell_view":{"cell_data":[{"video_data":[{"content_type":1,"series_id":"7470092475068071998","series_name":"目录测试"}]}],"has_more":false}}}"#
            }else{
                let html = #"<script>window._ROUTER_DATA={"loaderData":{"player_(series_id)/page":{"isSuccess":true,"seriesDetail":{"series_id":"7470092475068071998","series_name":"测试短剧","vid_list":["111","222"]}}}}</script>"#
                return(200,["Content-Type":"text/html"],Data(html.utf8))
            };return(200,["Content-Type":"application/json"],Data(json.utf8))
        }
        let meta=try await runtime.load(script:script);XCTAssertEqual(meta["id"] as? String,"dev.webox.hongguo")
        _ = try await runtime.invoke("filters")
        let search=try await runtime.invoke("search",["query":"测试","filters":[:]]) as! [String:Any]
        let card=(search["items"] as! [[String:Any]])[0];XCTAssertEqual(card["id"] as? String,"7470092475068071998")
        let detail=try await runtime.invoke("detail",["id":"7470092475068071998"]) as! [String:Any]
        let group=(detail["groups"] as! [[String:Any]])[0],episode=(group["episodes"] as! [[String:Any]])[0]
        let catalog=try await runtime.invoke("list",["filters":["category":"hot"]]) as! [String:Any]
        XCTAssertEqual((catalog["items"] as? [[String:Any]])?.first?["title"] as? String,"目录测试")
        let play=try await runtime.invoke("play",["contentId":"7470092475068071998","groupId":"main","episodeId":"111","episodeLink":episode["link"]!])
        let response=try JSONDecoder().decode(PlayResponse.self,from:JSONSerialization.data(withJSONObject:play))
        let plan=try XCTUnwrap(response.sources.first?.cenc);try plan.validate();XCTAssertTrue(plan.size>0)
    }
    @MainActor func testRealAVPlayerPlaybackSurvivesSourceSwitchAndResumes()async throws{
        let suite="webox-player-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!,folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app=AppModel(root:folder,defaults:defaults)
        defer{app.playback.stop();defaults.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:folder)}
        let(source,_)=try await app.install(Data(contentsOf:fixture("01-cinema.webox")),origin:"fixture.js")
        let(second,_)=try await app.install(Data(contentsOf:fixture("02-documents.widget")),origin:"fixture.widget.js")
        let runtime=try await app.makeRuntime(source);defer{runtime.close()}
        let raw=try await runtime.invoke("detail",["id":"1","title":"山海来信"])
        let detail=try JSONDecoder().decode(ContentDetail.self,from:JSONSerialization.data(withJSONObject:raw))
        let group=try XCTUnwrap(detail.groups.first),episode=try XCTUnwrap(group.episodes.first)
        let card=Card(id:"1",title:"山海来信")
        app.playback.play(PlaybackContext(source:source,card:card,detail:detail,group:group,episode:episode),app:app,resume:2,present:false)
        let deadline=Date().addingTimeInterval(25)
        while Date()<deadline && app.playback.elapsed<2.3 && app.playback.phase != .failed{try await Task.sleep(for:.milliseconds(100))}
        XCTAssertNotEqual(app.playback.phase,.failed,app.playback.error ?? "")
        XCTAssertGreaterThan(app.playback.elapsed,2.1)
        let player=app.playback.player;app.select(second)
        XCTAssertTrue(app.playback.player === player);XCTAssertEqual(app.playback.context?.source.id,source.id)
        app.playback.pause();app.playback.saveProgress();XCTAssertGreaterThan(app.saved(card,source:source)?.seconds ?? 0,2)
        app.playback.selectGroup(detail.groups[1]);XCTAssertEqual(app.playback.context?.group.id,detail.groups[1].id)
    }
}
