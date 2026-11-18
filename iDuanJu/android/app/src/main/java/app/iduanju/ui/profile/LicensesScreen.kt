package app.iduanju.ui.profile

import androidx.compose.foundation.layout.*
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.iduanju.ui.theme.IdjThemeColors

/** iOS LicensesView (我的 → 开源许可), Android libraries + the shared ports. */
@Composable
fun LicensesScreen(onBack: () -> Unit) {
    SettingsPage("开源许可", onBack) {
        Group {
            License("i短剧", "GPL-3.0 · 禁止付费分发", "本应用源码以 GPL-3.0 开源。")
            RowDivider()
            License("AndroidX · Jetpack Compose · Media3", "Apache License 2.0", "界面、播放器（ExoPlayer、HLS、OkHttp 数据源）。")
            RowDivider()
            License("OkHttp · Okio", "Apache License 2.0 · Square, Inc.", "网络请求。")
            RowDivider()
            License("Coil", "Apache License 2.0", "封面与漫画图片加载。")
            RowDivider()
            License("Kotlin · kotlinx.coroutines", "Apache License 2.0 · JetBrains", null)
            RowDivider()
            License("QuickJS", "MIT License", "插件运行时（经 QuickJS 包装库），沙箱封装为本应用代码。")
            RowDivider()
            License("Rhino 1.7.15", "Mozilla Public License 2.0", "小说书源脚本引擎，未修改；来源 github.com/mozilla/rhino，许可随安装包 assets/licenses 分发。")
            RowDivider()
            License("hongguo-open-player", "GPL-3.0-only · zfdang (commit 3f687c5)",
                "红果播放签名（Argus 551 / Ladon）参考其 src/server/native/argus.js 移植，与 iOS 实现逐字节一致。")
            RowDivider()
            License("红果当前播放器签名", "Apache-2.0 变换来源 · OpenHongguo 05aa580 / gateway 0613b49",
                "当前 Medusa 封装移植自 get_video_streaming，KS/自定义变换源自 OpenHongguo，已按原生合成向量验证。源码、修改范围和许可见仓库 THIRD_PARTY_NOTICES.md。")
            RowDivider()
            License("UAV-Downloader · yt-dlp · JMComic-Crawler-Python", "Apache-2.0 · Unlicense · MIT",
                "部分站点解析与 18comic 图片还原算法参考这些项目，代码为独立实现。")
            RowDivider()
            License("MangaDex API · 包子漫画 · Telegram 网页预览", null, "漫画与频道解析均为本应用独立实现；MangaDex 只请求全年龄 / 轻度分级内容。")
        }
    }
}

@Composable
private fun License(name: String, license: String?, note: String?) {
    val c = IdjThemeColors
    Column(Modifier.fillMaxWidth().padding(14.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text(name, color = c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        license?.let { Text(it, color = c.secondary, fontSize = 13.sp) }
        note?.let { Text(it, color = c.secondary, fontSize = 12.sp, lineHeight = 17.sp) }
    }
}

/** 剧星榜 is not ported to Android yet; say so instead of a dead row. */
@Composable
fun ActorRankPlaceholder(onBack: () -> Unit) {
    SettingsPage("剧星榜", onBack) {
        Group(footer = "iOS 版的剧星榜（演员热度榜、演员主页与作品）还没有移植到 Android。") {
            Text("暂未支持", color = IdjThemeColors.secondary, fontSize = 15.sp, modifier = Modifier.padding(14.dp))
        }
    }
}
