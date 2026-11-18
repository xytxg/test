package app.iduanju.huangguo

import android.annotation.SuppressLint
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.iduanju.IdjApp
import app.iduanju.core.util.CFDetect
import app.iduanju.core.util.VerificationRequiredException
import app.iduanju.ui.theme.IdjThemeColors
import okhttp3.Cookie
import okhttp3.CookieJar
import okhttp3.HttpUrl

/**
 * OkHttp jar over the system WebView CookieManager (persisted by WebView itself), so the cf_clearance the user
 * earns in [CFVerifyDialog] is reused by HuangguoClient; when it expires the site challenges again and the UI
 * returns to 「需要验证」.
 */
object WebViewCookieJar : CookieJar {
    override fun saveFromResponse(url: HttpUrl, cookies: List<Cookie>) {
        val cm = runCatching { CookieManager.getInstance() }.getOrNull() ?: return
        cookies.forEach { cm.setCookie(url.toString(), it.toString()) }
    }
    override fun loadForRequest(url: HttpUrl): List<Cookie> {
        val raw = runCatching { CookieManager.getInstance().getCookie(url.toString()) }.getOrNull() ?: return emptyList()
        return raw.split(';').mapNotNull { Cookie.parse(url, it.trim()) }
    }
}

/** 「需要验证」 inline state with 去验证 (opens the WebView) and 重试. */
@Composable
fun VerifyRequiredState(e: VerificationRequiredException, onRetry: () -> Unit) {
    val c = IdjThemeColors
    var show by remember { mutableStateOf(false) }
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("需要验证", color = c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        Text("${e.host} 开启了人机验证，请在页面中完成一次验证", color = c.secondary, fontSize = 13.sp)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Pill("去验证", filled = true) { show = true }
            Pill("重试", filled = false, onRetry)
        }
    }
    if (show) CFVerifyDialog(e.url, onDismiss = { show = false }, onPassed = { show = false; onRetry() })
}

@Composable
private fun Pill(label: String, filled: Boolean, onClick: () -> Unit) {
    val c = IdjThemeColors
    Box(Modifier.height(34.dp).clip(RoundedCornerShape(50)).background(if (filled) c.text else c.text.copy(0.08f))
        .clickable(onClick = onClick).padding(horizontal = 18.dp), contentAlignment = Alignment.Center) {
        Text(label, color = if (filled) c.bg else c.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
    }
}

/**
 * Visible system WebView at [url]. The user completes the Cloudflare check themselves — nothing here clicks,
 * solves or spoofs anything. We only watch for the page to stop being a challenge with a cf_clearance cookie,
 * then store the WebView's own UA so later requests match the clearance.
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun CFVerifyDialog(url: String, onDismiss: () -> Unit, onPassed: () -> Unit) {
    val c = IdjThemeColors
    var status by remember { mutableStateOf("请在下方页面完成验证") }
    var web by remember { mutableStateOf<WebView?>(null) }
    fun finish(w: WebView) {
        CookieManager.getInstance().flush()
        IdjApp.instance.huangguo.rememberVerifiedUA(w.settings.userAgentString)
        onPassed()
    }
    fun pageCleared(w: WebView) = (w.title ?: "").let { it.isNotBlank() && !CFDetect.isChallengeTitle(it) }
    fun hasClearance() = (CookieManager.getInstance().getCookie(url) ?: "").split(';').any { it.trim().startsWith("cf_clearance=") }
    // Auto-close only once Cloudflare issued cf_clearance; a plain WAF block may never set it, so 「完成」 also
    // accepts any non-challenge page (like iOS passedWithoutClearance) and the retry tells whether it worked.
    fun passed(w: WebView) = pageCleared(w) && hasClearance()
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Column(Modifier.fillMaxSize().background(c.bg).systemBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("关闭", color = c.secondary, fontSize = 15.sp, modifier = Modifier.clickable(onClick = onDismiss))
                Text("站点验证", color = c.text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                Text("完成", color = c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable {
                    val w = web ?: return@clickable
                    if (pageCleared(w)) finish(w) else status = "还未通过验证，请按页面提示完成后再点「完成」"
                })
            }
            Text(status, color = c.secondary, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
            AndroidView(modifier = Modifier.fillMaxSize(), factory = { ctx ->
                WebView(ctx).apply {
                    settings.javaScriptEnabled = true
                    settings.domStorageEnabled = true
                    CookieManager.getInstance().setAcceptCookie(true)
                    CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
                    webViewClient = object : WebViewClient() {
                        override fun onPageFinished(view: WebView, u: String?) {
                            if (passed(view)) { status = "验证已通过"; finish(view) }
                        }
                    }
                    loadUrl(url)
                    web = this
                }
            }, onRelease = { it.stopLoading(); it.destroy() })
        }
    }
}
