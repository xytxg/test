package app.iduanju

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.activity.enableEdgeToEdge
import androidx.test.platform.app.InstrumentationRegistry
import app.iduanju.core.novel.*
import app.iduanju.novel.NovelScreen
import app.iduanju.ui.theme.IdjTheme
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.After
import java.io.File
import java.util.concurrent.TimeUnit

/** Native UI, live unmodified user source. No NovelSources.fixture or sample books. */
class NovelRealParityTest {
    @get:Rule val ui=createAndroidComposeRule<androidx.activity.ComponentActivity>()
    private fun screenshot(name:String){
        ui.waitForIdle();android.os.SystemClock.sleep(700)
        val bmp=InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot()
        try {val out=java.io.ByteArrayOutputStream();bmp.compress(android.graphics.Bitmap.CompressFormat.PNG,100,out);saveNovelEvidence(name,out.toByteArray())}finally{bmp.recycle()}
    }
    @After fun restoreSourceStorage(){ NovelSources.fixture=null; NovelSources.configureStorage(InstrumentationRegistry.getInstrumentation().targetContext.filesDir) }
    @Test fun realQimaoRankingDetailAndReader(){
        // A fresh-flow scenario must not inherit expanded/selected source filters from earlier tests.
        val isolatedContext=InstrumentationRegistry.getInstrumentation().targetContext
        NovelSources.configureStorage(File(isolatedContext.cacheDir,"novel-live-acceptance-"+java.util.UUID.randomUUID()))
        saveNovelEvidence("parity-android-real-flow-current.json",org.json.JSONObject().put("flowCompleted",false).put("startedAtMs",System.currentTimeMillis()).put("readerParityComplete",false).toString(2).toByteArray())
        NovelSources.fixture=null
        val raw=InstrumentationRegistry.getInstrumentation().context.assets.open("real-1335.json").bufferedReader().use{it.readText()}
        assertEquals("874efe33cbe38b7dcf830704b5bd0614b9485fe1974a20d9c09030ebec07df30",java.security.MessageDigest.getInstance("SHA-256").digest(raw.toByteArray()).joinToString(""){"%02x".format(it)})
        val all=NovelSources.import(raw);val source=all.first{it.name=="七猫小说"}
        val ctx=InstrumentationRegistry.getInstrumentation().targetContext
        ctx.getSharedPreferences("novel",0).edit().clear().putString("sources",raw).putString("rankSource",source.id).commit()
        ui.runOnUiThread{ui.activity.enableEdgeToEdge()}
        ui.setContent{IdjTheme(dark=false){NovelScreen({})}}
        ui.onNodeWithText("排行榜").performClick()
        ui.waitUntil(60000){ui.onAllNodesWithText("爽文",substring=false).fetchSemanticsNodes().isNotEmpty()}
        ui.onNodeWithText("爽文",substring=false).performScrollTo().performClick()
        ui.waitUntil(60000){ui.onAllNodesWithText("无敌天命",substring=false).fetchSemanticsNodes().isNotEmpty()}
        screenshot("parity-android-01-real-rank.png")
        ui.onNodeWithText("无敌天命",substring=false).performClick()
        ui.waitUntil(60000){runCatching{ui.onNodeWithTag("novel.detail.read").assertIsEnabled()}.isSuccess}
        ui.onNodeWithText("青鸾峰上",substring=false).assertIsDisplayed()
        ui.onNodeWithTag("novel.detail.intro").assertTextContains("谁言天命天注定",substring=true)
        screenshot("parity-android-02-real-detail.png")
        // Re-runs preserve existing real-book cache instead of deleting simulator progress.
        if(runCatching{ui.onNodeWithTag("novel.detail.add").assertIsEnabled()}.isSuccess)
            ui.onNodeWithTag("novel.detail.add").performClick()
        ui.waitUntil(10000){runCatching{ui.onNodeWithTag("novel.detail.add").assertIsNotEnabled()}.isSuccess}
        val cache=NovelCache(File(ctx.filesDir,"novel-cache-v2"));assertTrue(cache.books().any{it.source==source.id&&it.book.name=="无敌天命"})
        ui.onNodeWithTag("novel.detail.source").performClick()
        ui.onNodeWithText("搜索其他书源",substring=false).assertIsDisplayed()
        screenshot("parity-android-02a-source-menu.png")
        ui.onNodeWithText(source.name,substring=false).performClick()
        ui.onNodeWithTag("novel.detail.download").performClick()
        ui.waitUntil(10000){runCatching{ui.onNodeWithText("缓存与下载").assertIsDisplayed()}.isSuccess}
        screenshot("parity-android-03-real-download.png")
        ui.onNodeWithText("返回",substring=false).performClick()
        ui.onNodeWithTag("novel.detail.read").performClick()
        ui.waitUntil(60000){ui.onAllNodesWithTag("novel.page").fetchSemanticsNodes().isNotEmpty()}
        screenshot("parity-android-04-real-native-reader.png")
        val saved=cache.books().first{it.source==source.id&&it.book.name=="无敌天命"}
        assertTrue(saved.chapters.size>1600)
        assertTrue(cache.read(source.id,saved.book.url,saved.chapters.first().url)!!.contains("青州"))
        // Explicit fresh parser/network check, even when the native reader preserved an older real cache.
        val fresh=NovelSources.content(source,saved.chapters.first(),saved.chapters.getOrNull(1)?.url,saved.book.url)
        assertTrue(fresh.contains("青州"));assertTrue(fresh.length>1000)
        // Verify production neighbor prefetch and offline foreground reuse on the SAME real book.
        ui.waitUntil(90000){cache.read(source.id,saved.book.url,saved.chapters[1].url)!=null}
        try {
            NovelSources.fixture={error("Offline verification: no requests permitted")}
            ui.onNodeWithTag("novel.page").performTouchInput{click(center)}
            ui.onNodeWithTag("novel.menu.toc").performClick()
            ui.onNodeWithTag("novel.chapter.1").performClick()
            ui.waitUntil(20000){org.json.JSONObject(ctx.getSharedPreferences("novel",0).getString("last","{}")!!).optInt("chapter",-1)==1}
            ui.onNodeWithTag("novel.page").assertContentDescriptionContains(saved.chapters[1].title,substring=true)
            ui.onNodeWithTag("novel.page").performTouchInput{click(center)}
            ui.onNodeWithTag("novel.menu.toc").performClick()
            ui.onNodeWithTag("novel.toc").performScrollToIndex(0)
            ui.onNodeWithTag("novel.chapter.0").performClick()
            ui.waitUntil(20000){org.json.JSONObject(ctx.getSharedPreferences("novel",0).getString("last","{}")!!).optInt("chapter",-1)==0}
            ui.onNodeWithTag("novel.page").assertContentDescriptionContains(saved.chapters[0].title,substring=true)
        }finally{NovelSources.fixture=null}
        saveNovelEvidence("parity-android-real-flow-current.json",org.json.JSONObject().put("flowCompleted",true).put("finishedAtMs",System.currentTimeMillis()).put("collection","https://www.yckceo.com/yuedu/shuyuans/json/id/1335.json").put("collectionSha256",java.security.MessageDigest.getInstance("SHA-256").digest(raw.toByteArray()).joinToString(""){"%02x".format(it)}).put("source",source.name).put("book",saved.book.name).put("toc",saved.chapters.size).put("freshChapterLength",fresh.length).put("offlineChapterNavigation",true).put("readerParityComplete",false).toString(2).toByteArray())
    }
}
