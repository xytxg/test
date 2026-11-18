import XCTest
@testable import STV

/// Issue #12: huangguo.video answers URLSession with a Cloudflare challenge. The client must surface
/// 「需要验证」 (SiteError.needsVerification) for the visible verify sheet, never parse it as an empty list,
/// and afterwards reuse the WebView's cookies with the same UA.
final class HuangguoCFTests: XCTestCase {
    private let page = URL(string: "https://huangguo.video/videos?page=1")!

    private let attention = """
    <!DOCTYPE html><html lang="en-US"><head><title>Attention Required! | Cloudflare</title></head>
    <body><div id="cf-wrapper"><h1>Sorry, you have been blocked</h1>
    <script>window._cf_chl_opt={cvId:'3'};</script></div></body></html>
    """

    func testAttentionRequired403IsVerification() throws {
        let e = HuangguoClient.challengeError(url: page, status: 403, headers: ["Server": "cloudflare"], body: Data(attention.utf8))
        let t = try XCTUnwrap(e?.verifyTarget)
        XCTAssertEqual(t.source, .huangguo)
        XCTAssertEqual(t.url, "https://huangguo.video/")
    }

    func testManagedChallengeHeaderIsVerification() {
        let e = HuangguoClient.challengeError(url: page, status: 403, headers: ["cf-mitigated": "challenge"], body: Data("<html></html>".utf8))
        XCTAssertNotNil(e?.verifyTarget)
    }

    func testJustAMoment503IsVerification() {
        let html = "<html><head><title>Just a moment...</title></head><body></body></html>"
        XCTAssertNotNil(HuangguoClient.challengeError(url: page, status: 503, headers: ["server": "cloudflare"], body: Data(html.utf8)))
    }

    func testRealPageWithCFScriptIsNotVerification() {
        let html = "<html><head><title>黄果视频</title></head><body>" + String(repeating: "<div class=\"card\">x</div>", count: 50)
            + "<script src=\"/cdn-cgi/challenge-platform/scripts/jsd/main.js\"></script></body></html>"
        XCTAssertNil(HuangguoClient.challengeError(url: page, status: 200, headers: ["Server": "cloudflare"], body: Data(html.utf8)))
    }

    func testPlainUpstreamErrorIsNotVerification() {
        XCTAssertNil(HuangguoClient.challengeError(url: page, status: 502, headers: [:], body: Data("Bad gateway".utf8)))
    }

    func testLearnedUAOnlyForChallengedHost() {
        defer { SiteUA.clear(.huangguo) }
        SiteUA.clear(.huangguo)
        XCTAssertEqual(HuangguoClient.userAgent(for: page), HuangguoClient.userAgent)
        SiteUA.set("WebViewUA/1.0", for: .huangguo)
        XCTAssertEqual(HuangguoClient.userAgent(for: page), "WebViewUA/1.0")
        XCTAssertEqual(HuangguoClient.userAgent(for: URL(string: "https://www.huangguo.video/x")!), "WebViewUA/1.0")
        XCTAssertEqual(HuangguoClient.userAgent(for: URL(string: "https://hgai12.com/")!), HuangguoClient.userAgent)
    }

    func testClearanceCookieSyncsIntoAppJar() throws {
        let jar = HTTPCookieStorage.shared
        // Isolate the test from cookies set by real simulator verification (e.g. _hgs), then restore them.
        let saved = (jar.cookies ?? []).filter { $0.domain.hasSuffix("huangguo.video") }
        saved.forEach { jar.deleteCookie($0) }
        defer {
            for c in jar.cookies ?? [] where c.domain.hasSuffix("huangguo.video") { jar.deleteCookie(c) }
            saved.forEach { jar.setCookie($0) }
        }
        let c = try XCTUnwrap(HTTPCookie(properties: [.domain: ".huangguo.video", .path: "/", .name: "cf_clearance", .value: "v",
                                                      .secure: "TRUE", .expires: Date().addingTimeInterval(3600)]))
        let other = try XCTUnwrap(HTTPCookie(properties: [.domain: "example.com", .path: "/", .name: "x", .value: "y"]))
        let synced = CFCookies.sync([c, other], host: "huangguo.video", into: jar)
        XCTAssertEqual(synced.map(\.name), ["cf_clearance"])
        XCTAssertEqual(jar.cookies(for: page)?.map(\.name), ["cf_clearance"])
        XCTAssertTrue(CFCookies.isSiteCookie(c))
    }
}
