package app.iduanju.core.util

/**
 * A request hit a Cloudflare challenge. The user has to pass it themselves in a visible WebView at [url]
 * (no automated solving); the UI shows 「需要验证」 with 去验证 / 重试 instead of a plain failure.
 */
class VerificationRequiredException(val url: String, val host: String) :
    Exception("需要验证：$host 开启了 Cloudflare 人机验证，请点「去验证」完成后重试")

/** Mirrors iOS CFDetect: interstitial / managed-challenge detection that ignores real pages embedding CF scripts. */
object CFDetect {
    val challengeTitles = listOf("just a moment", "请稍候", "請稍候", "attention required", "please wait",
        "un instant", "einen moment", "しばらくお待ちください", "잠시만 기다리")

    fun title(html: String): String =
        Regex("<title[^>]*>([^<]*)</title>", RegexOption.IGNORE_CASE).find(html.take(20_000))?.groupValues?.get(1)?.trim() ?: ""

    fun isChallengeTitle(t: String): Boolean { val l = t.lowercase(); return challengeTitles.any { l.contains(it) } }

    /** [header] looks a response header up case-insensitively. */
    fun isChallenge(status: Int, header: (String) -> String?, body: String): Boolean {
        if (header("cf-mitigated")?.lowercase() == "challenge") return true
        val head = body.take(8000).lowercase()
        if (isChallengeTitle(title(body))) return true
        if (head.contains("window._cf_chl_opt") || head.contains("cf_chl_opt") || head.contains("id=\"challenge-form\"")
            || head.contains("cf-browser-verification") || head.contains("id=\"challenge-stage\"")) return true
        val cfServer = header("server")?.lowercase()?.contains("cloudflare") == true
        if ((status == 403 || status == 503) && (cfServer || head.contains("cloudflare"))) {
            // 403 with real cards is a soft block we can still parse; otherwise it needs the browser.
            return body.length < 30_000 || head.contains("challenge-platform")
        }
        return false
    }

    /** RFC 6265 domain match: ".huangguo.video" / "huangguo.video" matches "huangguo.video" and "www.huangguo.video". */
    fun domainMatches(cookieDomain: String, host: String): Boolean {
        val d = cookieDomain.lowercase().trim('.'); val h = host.lowercase()
        return d.isNotEmpty() && (h == d || h.endsWith(".$d"))
    }
}
