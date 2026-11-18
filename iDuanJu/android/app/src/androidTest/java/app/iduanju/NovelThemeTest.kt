package app.iduanju

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import app.iduanju.core.novel.NovelSources
import app.iduanju.novel.NovelScreen
import app.iduanju.ui.theme.IdjTheme
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import java.io.File

class NovelThemeTest {
    @get:Rule val ui = createComposeRule()
    @Before fun seed() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val source=JSONObject().put("bookSourceUrl","https://preview.invalid").put("bookSourceName","界面验收 · 合成数据")
            .put("searchUrl","/search").put("exploreUrl","全部::\n月票榜::/rank/month\n畅销榜::/rank/sales\n玄幻::\n热门榜::/fantasy")
            .put("ruleSearch",JSONObject().put("bookList","$.books[*]").put("name","$.name").put("bookUrl","$.url").put("author","$.author").put("kind","$.kind"))
            .put("ruleBookInfo",JSONObject().put("tocUrl","$.toc"))
            .put("ruleToc",JSONObject().put("chapterList","$.chapters[*]").put("chapterName","$.title").put("chapterUrl","$.url"))
            .put("ruleContent",JSONObject().put("content","$.content"))
        context.getSharedPreferences("novel",0).edit().clear().putString("sources",JSONArray().put(source).toString()).commit()
        NovelSources.fixture={
            val books=JSONArray()
            listOf("雾港","灯塔来信","长夜星河","山海之间").forEachIndexed { i,title ->
                books.put(JSONObject().put("name",title).put("author","测试作者").put("kind","奇幻 · 连载").put("url","https://preview.invalid/book/$i"))
            }
            val chapters=JSONArray()
            repeat(200){i->chapters.put(JSONObject().put("title","第${i+1}章").put("url","https://preview.invalid/chapter/$i"))}
            JSONObject().put("books",books).put("toc","https://preview.invalid/toc").put("chapters",chapters).put("content","合成离线正文").toString()
        }
        val cache=app.iduanju.core.novel.NovelCache(File(context.filesDir,"novel-cache-v2"))
        NovelSources.search(app.iduanju.core.novel.NovelSource(source),"fixture").forEach { book ->
            cache.saveBook("https://preview.invalid",book,NovelSources.chapters(app.iduanju.core.novel.NovelSource(source),book.url))
        }
        org.junit.Assert.assertEquals(4,NovelSources.search(app.iduanju.core.novel.NovelSource(source),"",category=app.iduanju.core.novel.NovelCategory("月票榜","/rank/month")).size)
    }
    @After fun cleanup(){NovelSources.fixture=null}
    private fun screenshot(name:String){
        ui.waitForIdle()
        // Hardware capture can precede the first submitted frame even after Compose is idle.
        android.os.SystemClock.sleep(700)
        val instrumentation=InstrumentationRegistry.getInstrumentation()
        val path=File(instrumentation.targetContext.getExternalFilesDir(null),"novel-$name.png")
        val bitmap=instrumentation.uiAutomation.takeScreenshot()
        try { path.outputStream().use{bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,it)} }
        finally {bitmap.recycle()}
        saveNovelEvidence(path.name,path.readBytes())
    }
    private fun verify(dark:Boolean){
        val style=if(dark)"dark" else "light"
        app.iduanju.ui.home.HomeJump.label="小说"
        ui.setContent{IdjTheme(dark=dark){app.iduanju.ui.RootScreen()}}
        ui.onNodeWithText("我的书架").assertIsDisplayed()
        screenshot("$style-04-shelf-fixture")
        ui.onNodeWithText("排行榜").performClick()
        ui.waitUntil(10000){ui.onAllNodesWithText("月票榜").fetchSemanticsNodes().isNotEmpty()}
        ui.onNodeWithText("月票榜").performClick()
        ui.waitUntil(10000){ui.onAllNodesWithText("雾港",substring=false).fetchSemanticsNodes().isNotEmpty()}
        screenshot("$style-06-rank-fixture")
        ui.onNodeWithContentDescription("搜书").performClick()
        ui.onNodeWithText("书源",substring=false).performClick()
        ui.onNodeWithText("共 1 个书源 · 已启用 1 个").assertIsDisplayed()
        screenshot("$style-08-sources-fixture")
        ui.onNodeWithContentDescription("导入书源").performClick()
        ui.onNodeWithText("导入书籍与书源").assertIsDisplayed()
        screenshot("$style-07-import-fixture")
        ui.onNodeWithContentDescription("关闭").performClick()
        ui.onNodeWithContentDescription("返回").performClick()
        ui.onNode(hasSetTextAction()).performTextInput("雾港")
        ui.onNodeWithText("搜索",substring=false).performClick()
        ui.waitUntil(10000){ui.onAllNodesWithText("雾港",substring=false).fetchSemanticsNodes().isNotEmpty()}
        screenshot("$style-05-search-fixture")
        ui.onAllNodesWithText("雾港",substring=false).onLast().performClick()
        ui.waitUntil(10000){ui.onAllNodesWithTag("novel.detail.download").fetchSemanticsNodes().isNotEmpty()}
        ui.waitUntil(10000){runCatching{ui.onNodeWithTag("novel.detail.download").assertIsEnabled()}.isSuccess}
        screenshot("$style-detail")
        ui.onNodeWithTag("novel.detail.download").performClick()
        try {ui.waitUntil(5000){ui.onAllNodesWithText("缓存与下载").fetchSemanticsNodes().isNotEmpty()}}
        catch(e:Exception){screenshot("$style-download-failed");ui.onRoot().printToLog("NovelUI");throw e}
        screenshot("$style-download")
        ui.onNodeWithText("缓存与下载").assertIsDisplayed()
        ui.onNodeWithText("缓存后 50 章").performClick()
        val ctx=InstrumentationRegistry.getInstrumentation().targetContext
        val nc=app.iduanju.core.novel.NovelCache(File(ctx.filesDir,"novel-cache-v2"))
        ui.waitUntil(30000){nc.books().any{it.book.name=="雾港" && nc.count(it.source,it.book.url,it.chapters)>=50}}
        screenshot("$style-download-50-complete")
    }
    @Test fun lightThemeFlow(){verify(false)}
    @Test fun darkThemeFlow(){verify(true)}
}
