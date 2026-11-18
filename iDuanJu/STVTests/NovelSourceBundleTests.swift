import XCTest
@testable import STV

final class NovelSourceBundleTests: XCTestCase {
    func testBoundedMemoryStreamsGzipAndBigIntegers() throws {
        let source = LegadoSource(bookSourceUrl: "https://compat.test", bookSourceName: "test", searchUrl: nil)
        let context = LegadoContext(source: source)
        let code = """
        var B=Packages.java.math.BigInteger;var out=new Packages.java.io.ByteArrayOutputStream();var gzip=new Packages.java.util.zip.GZIPOutputStream(out);gzip.write(new Packages.java.lang.String('中文 stream').getBytes());gzip.close();var reader=new Packages.java.io.BufferedReader(new Packages.java.io.InputStreamReader(new Packages.java.util.zip.GZIPInputStream({bytes:out.toByteArray()}),'UTF-8'));reader.readLine()+'|'+new B('12345678901234567890').modPow(new B('65537'),new B('999999999999999999989')).toString()+'|'+new B('128').toByteArray().join(',');
        """
        XCTAssertEqual(try context.evalJS(code, result: nil, baseURL: source.id) as? String, "中文 stream|578379236927338162488|0,-128")
        XCTAssertThrowsError(try context.evalJS("new Packages.java.security.SecureRandom().generateSeed(99999999)", result: nil, baseURL: source.id))
        XCTAssertThrowsError(try context.evalJS("new Packages.java.net.URL('file:///etc/passwd').openConnection().getResponseCode()", result: nil, baseURL: source.id))
    }

    func testTOCSkipsVolumeAndContentPreservesFragment() throws {
        let s = LegadoSource(bookSourceUrl: "https://fragment.test", bookSourceName: "test", searchUrl: nil,
            ruleToc: ["chapterList":"$.chapters[*]","chapterName":"$.name","chapterUrl":"$.url","isVolume":"$.volume"],
            ruleContent: ["content":"@js:String(baseUrl)"])
        LegadoHTTP.transport = { r in
            let body = #"{"chapters":[{"name":"卷一","url":"","volume":true},{"name":"第一章","url":"/book#chapter1"}]}"#
            return (Data(body.utf8), HTTPURLResponse(url: URL(string:"https://fragment.test/book")!,statusCode:200,httpVersion:nil,headerFields:nil)!)
        }
        defer { LegadoHTTP.transport = nil }
        let toc = try LegadoClient.toc(s,tocURL:s.id+"/book")
        XCTAssertEqual(toc.count,1)
        XCTAssertEqual(try LegadoClient.content(s,chapter:toc[0],nextChapterURL:nil),"https://fragment.test/book#chapter1")
    }
    func testGroupedDiscoveryHeadersAndTemplateOptions() throws {
        let categories = try LegadoClient.parseExploreCategories("分类::\n玄幻::/fantasy\n榜单\n月票榜::/month\n榜单::\n月票榜::/month")
        XCTAssertEqual(categories.map(\.title), ["玄幻", "月票榜"])
        XCTAssertEqual(categories.map(\.group), ["分类", "榜单"])
        let source = LegadoSource(bookSourceUrl: "https://options.test", bookSourceName: "test", searchUrl: nil)
        let request = try LegadoURL.request(#"{{'/rank,{"headers":{"X-Source":"ok"},"method":"POST","body":"page=1"}'}}"#, ctx: LegadoContext(source: source), base: source.id)
        XCTAssertEqual(request.request.url?.absoluteString, "https://options.test/rank")
        XCTAssertEqual(request.request.value(forHTTPHeaderField: "X-Source"), "ok")
        XCTAssertEqual(request.request.httpMethod, "POST")
    }

    private func sources() throws -> [LegadoSource] {
        guard let path = ProcessInfo.processInfo.environment["STV_NOVEL_COLLECTION"] else { throw XCTSkip("STV_NOVEL_COLLECTION points at user-supplied 1335.json") }
        return try LegadoSourceStore.parse(Data(contentsOf: URL(fileURLWithPath: path)))
    }

    func testBundleHasUsableTextSourcesAndRankGroups() throws {
        let all = try sources()
        XCTAssertGreaterThanOrEqual(all.count, 150)
        let text = all.filter { ($0.bookSourceType ?? 0) == 0 }
        XCTAssertGreaterThanOrEqual(text.count, 140)
        let cats = try LegadoClient.exploreCategories(try XCTUnwrap(text.first(where: { $0.bookSourceName == "猫扑中文" })))
        XCTAssertTrue(cats.contains { $0.title == "排行榜" && !$0.url.isEmpty })
        XCTAssertTrue(cats.contains { $0.group == "推荐" && $0.title == "玄幻奇幻" })
        XCTAssertFalse(cats.contains { $0.url.isEmpty && $0.action == nil })
    }

    func testExploreNeverFallsBackToDetailPage() throws {
        var source = LegadoSource(bookSourceUrl: "https://book.test", bookSourceName: "test", searchUrl: "/search")
        source.exploreUrl = "排行榜::data:text/html,<html><body>无列表</body></html>"
        source.ruleExplore = ["bookList": "class.none", "name": "tag.a@text", "bookUrl": "tag.a@href"]
        let cats = try LegadoClient.exploreCategories(source)
        XCTAssertTrue(try LegadoClient.explore(source, category: cats[0]).isEmpty)
    }
}
