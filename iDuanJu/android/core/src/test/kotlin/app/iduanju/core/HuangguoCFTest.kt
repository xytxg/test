package app.iduanju.core

import app.iduanju.core.huangguo.HuangguoClient
import app.iduanju.core.util.CFDetect
import org.junit.Assert.*
import org.junit.Test

/** Issue #12: huangguo.video Cloudflare challenge → 「需要验证」, real pages untouched, same UA after verify. */
class HuangguoCFTest {
    private val page = "https://huangguo.video/videos?page=1"
    private fun h(vararg kv: Pair<String, String>): (String) -> String? = { n -> kv.firstOrNull { it.first.equals(n, true) }?.second }
    private val attention = """<!DOCTYPE html><html lang="en-US"><head><title>Attention Required! | Cloudflare</title></head>
        <body><div id="cf-wrapper"><h1>Sorry, you have been blocked</h1><script>window._cf_chl_opt={cvId:'3'};</script></div></body></html>"""

    @Test fun attentionRequired403NeedsVerification() {
        val e = HuangguoClient.challengeError(page, 403, h("Server" to "cloudflare"), attention)
        assertNotNull(e); assertEquals("https://huangguo.video/", e!!.url); assertEquals("huangguo.video", e.host)
        assertTrue(e.message!!.startsWith("需要验证"))
    }
    @Test fun managedChallengeHeader() = assertNotNull(HuangguoClient.challengeError(page, 403, h("cf-mitigated" to "challenge"), "<html></html>"))
    @Test fun justAMoment503() = assertNotNull(HuangguoClient.challengeError(page, 503, h("server" to "cloudflare"), "<html><head><title>Just a moment...</title></head></html>"))
    @Test fun localizedTitle() = assertTrue(CFDetect.isChallenge(200, h(), "<title>请稍候…</title>"))

    @Test fun realPageWithCFScriptIsNotChallenge() {
        val html = "<html><head><title>黄果视频</title></head><body>" + "<div class=\"card\">x</div>".repeat(50) +
            "<script src=\"/cdn-cgi/challenge-platform/scripts/jsd/main.js\"></script></body></html>"
        assertNull(HuangguoClient.challengeError(page, 200, h("Server" to "cloudflare"), html))
    }
    @Test fun plainUpstreamErrorIsNotChallenge() = assertNull(HuangguoClient.challengeError(page, 502, h(), "Bad gateway"))

    @Test fun learnedUAOnlyForChallengedHost() {
        val prefs = java.util.concurrent.ConcurrentHashMap<String, String>()
        val c = HuangguoClient(null, prefs)
        assertEquals(HuangguoClient.UA, c.userAgent(page))
        c.rememberVerifiedUA("WebViewUA/1.0")
        assertEquals("WebViewUA/1.0", c.userAgent(page))
        assertEquals("WebViewUA/1.0", c.userAgent("https://www.huangguo.video/x"))
        assertEquals(HuangguoClient.UA, c.userAgent("https://hgai12.com/"))
        c.clearVerification(); assertEquals(HuangguoClient.UA, c.userAgent(page))
    }
    @Test fun domainMatch() {
        assertTrue(CFDetect.domainMatches(".huangguo.video", "huangguo.video"))
        assertTrue(CFDetect.domainMatches("huangguo.video", "www.huangguo.video"))
        assertFalse(CFDetect.domainMatches("huangguo.video", "evilhuangguo.video"))
        assertTrue(HuangguoClient.isCFHost("huangguo.video")); assertFalse(HuangguoClient.isCFHost("hgai12.com"))
    }

    /** Live (`-Plive=1`): from a network Cloudflare challenges, the 视频站 list surfaces 「需要验证」, not 「HTTP 403」. */
    @Test fun liveVideoListSurfacesVerification() {
        org.junit.Assume.assumeTrue(System.getProperty("idj.live") == "1")
        val c = HuangguoClient()
        val r = runCatching { c.list(HuangguoClient.videoChannels.first(), 1) }
        val e = r.exceptionOrNull()
        println("[live] huangguo.video list: ${if (r.isSuccess) "ok ${r.getOrNull()?.items?.size} items" else "${e!!::class.simpleName}: ${e.message}"}")
        if (r.isFailure) assertTrue("challenge must map to verification, got $e", e is app.iduanju.core.util.VerificationRequiredException || e?.message?.contains("HTTP 403") != true)
    }
}
