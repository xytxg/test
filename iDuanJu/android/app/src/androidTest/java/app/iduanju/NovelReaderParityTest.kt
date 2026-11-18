package app.iduanju

import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.activity.enableEdgeToEdge
import androidx.test.platform.app.InstrumentationRegistry
import app.iduanju.core.novel.*
import app.iduanju.novel.NovelScreen
import app.iduanju.ui.theme.IdjTheme
import org.json.JSONObject
import org.junit.*
import org.junit.Assert.*
import java.io.File

/** Actual production navigation/screens, exact source JSON and real previously fetched book/cache.
 * No network dependency or invented chapter text is allowed in this native parity test.
 */
class NovelReaderParityTest {
    @get:Rule val ui=createAndroidComposeRule<androidx.activity.ComponentActivity>()
    private val ctx get()=InstrumentationRegistry.getInstrumentation().targetContext
    private val prefs get()=ctx.getSharedPreferences("novel",0)
    private fun shot(name:String){ui.waitForIdle();android.os.SystemClock.sleep(350);val b=InstrumentationRegistry.getInstrumentation().uiAutomation.takeScreenshot();try{val out=java.io.ByteArrayOutputStream();b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,out);saveNovelEvidence("reader-android-$name.png",out.toByteArray())}finally{b.recycle()}}
    private fun setting()=JSONObject(prefs.getString("reader.settings","{}")!!)
    private fun slider(tag:String,v:Float){ui.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.SetProgress){it(v)};ui.waitForIdle()}
    @After fun cleanup(){NovelSources.fixture=null}
    @Test fun currentIosReaderControlsAndRealTOC(){
        val raw=InstrumentationRegistry.getInstrumentation().context.assets.open("real-1335.json").bufferedReader().use{it.readText()}
        assertEquals("874efe33cbe38b7dcf830704b5bd0614b9485fe1974a20d9c09030ebec07df30",java.security.MessageDigest.getInstance("SHA-256").digest(raw.toByteArray()).joinToString(""){"%02x".format(it)})
        val source=NovelSources.import(raw).first{it.name=="七猫小说"}
        val cache=NovelCache(File(ctx.filesDir,"novel-cache-v2"));val book=cache.books().first{it.source==source.id&&it.book.name=="无敌天命"}
        assertEquals(1694,book.chapters.size)
        assertTrue(cache.read(source.id,book.book.url,book.chapters[0].url)!!.contains("青州"))
        assertNotNull(cache.read(source.id,book.book.url,book.chapters[1].url))
        prefs.edit().clear().putString("sources",raw).putString("rankSource",source.id).putString("reader.settings","{\"font\":18,\"spacing\":0.5,\"margin\":0.3,\"indent\":true,\"theme\":0,\"turn\":\"slide\",\"fontID\":\"system\"}").commit()
        NovelSources.fixture={error("Offline native parity test: network forbidden")}
        ui.runOnUiThread{ui.activity.enableEdgeToEdge()}
        ui.setContent{IdjTheme(dark=false){NovelScreen({})}}
        ui.onAllNodesWithText("无敌天命",substring=false).onLast().performClick()
        ui.waitUntil(10000){runCatching{ui.onNodeWithTag("novel.detail.read").assertIsEnabled()}.isSuccess}
        shot("01-real-detail")
        ui.onNodeWithTag("novel.detail.read").performClick()
        ui.waitUntil(10000){ui.onAllNodesWithTag("novel.page").fetchSemanticsNodes().isNotEmpty()}
        ui.onNodeWithTag("novel.page").assertContentDescriptionContains("青州",substring=true)
        ui.onAllNodesWithContentDescription("设置").assertCountEquals(0)
        val canvasBefore=ui.onNodeWithTag("novel.page").fetchSemanticsNode().boundsInRoot
        shot("02-reader-white")
        ui.onNodeWithTag("novel.page").performTouchInput{click(center)}
        ui.onNodeWithTag("novel.menu.font").assertIsDisplayed()
        assertEquals("Reader viewport must not resize when overlay controls appear",canvasBefore,ui.onNodeWithTag("novel.page").fetchSemanticsNode().boundsInRoot)
        shot("03-menu")
        ui.onNodeWithTag("novel.menu.font").performClick();shot("04-settings")
        slider("novel.font.size",10f/18);assertEquals(22,setting().getInt("font"))
        slider("novel.margin",.8f);slider("novel.spacing",.9f)
        ui.onNodeWithTag("novel.indent").performClick();assertFalse(setting().getBoolean("indent"));shot("05-reflow")
        slider("novel.font.size",1f/3);slider("novel.margin",.3f);slider("novel.spacing",.5f);ui.onNodeWithTag("novel.indent").performClick()
        ui.onNodeWithTag("novel.fonts").performClick();ui.onNodeWithTag("novel.font.songti").performClick();assertEquals("songti",setting().getString("fontID"));ui.onNodeWithTag("novel.font.system").performClick();shot("06-fonts")
        ui.onNodeWithTag("novel.panel.back").performClick();ui.onNodeWithTag("novel.turn").performClick()
        val positionKey="reader.offset.${source.id}|${book.book.url}.0"
        fun offset()=prefs.getInt(positionKey,0)
        for(mode in listOf("curl","cover","none","slide")){
            ui.onNodeWithTag("novel.turn.$mode").performClick();assertEquals(mode,setting().getString("turn"))
            ui.onNodeWithTag("novel.page").performTouchInput{click(center)}
            ui.onNodeWithTag("novel.menu.font").assertDoesNotExist()
            val before=offset()
            ui.onNodeWithTag("novel.page").performTouchInput{swipeLeft()}
            ui.waitUntil(10000){offset()>before}
            shot("07-gesture-$mode")
            ui.onNodeWithTag("novel.page").performTouchInput{swipeRight()}
            ui.waitUntil(10000){offset()==before}
            // Rapid successive center taps must not be swallowed as an unhandled double tap.
            ui.onNodeWithTag("novel.page").performTouchInput{click(center)}
            ui.onNodeWithTag("novel.menu.font").assertIsDisplayed()
            ui.onNodeWithTag("novel.page").performTouchInput{click(center)}
            ui.onNodeWithTag("novel.menu.font").assertDoesNotExist()
            ui.onNodeWithTag("novel.page").performTouchInput{click(center)}
            ui.onNodeWithTag("novel.menu.font").performClick();ui.onNodeWithTag("novel.turn").performClick()
        }
        shot("07-turn-modes")
        ui.onNodeWithTag("novel.menu.light").performClick()
        for(theme in 0..3){ui.onNodeWithTag("novel.theme.$theme").performClick();assertEquals(theme,setting().getInt("theme"));shot("08-theme-$theme")}
        slider("novel.brightness",.4f);ui.onNodeWithTag("novel.theme.0").performClick()
        ui.onNodeWithTag("novel.menu.progress").performClick();shot("09-progress")
        ui.onNodeWithTag("novel.menu.info").performClick();shot("10-info")
        ui.onNodeWithTag("novel.menu.toc").performClick();shot("13-real-toc");ui.onNodeWithText("当前读到").assertIsDisplayed();
        val actualText=cache.read(source.id,book.book.url,book.chapters[0].url)!!.lines().map{it.trim()}.filter{it.isNotBlank()}.joinToString("\n")
        val query=Regex("[\\p{IsHan}]{6,}").find(actualText,1000)!!.value.take(6)
        val hit=cache.search(source.id,book.book.url,book.chapters,query).first{it.chapter==0&&it.offset>=1000}
        ui.onNodeWithTag("novel.toc.search").performTextInput(query);ui.onNodeWithTag("novel.toc.search").performImeAction()
        val hitTag="novel.toc.hit.0.${hit.offset}"
        ui.waitUntil(10000){ui.onAllNodesWithTag(hitTag).fetchSemanticsNodes().isNotEmpty()}
        ui.onNodeWithTag(hitTag).performScrollTo().performClick()
        ui.waitUntil(10000){offset()>0}
        ui.onNodeWithTag("novel.toc").assertDoesNotExist()
        ui.onNodeWithTag("novel.page").performTouchInput{click(center)};ui.onNodeWithTag("novel.menu.toc").performClick()
        ui.onNodeWithTag("novel.chapter.1").performClick()
        ui.waitUntil(10000){JSONObject(prefs.getString("last","{}")!!).optInt("chapter",-1)==1}
        ui.onNodeWithTag("novel.page").assertContentDescriptionContains(book.chapters[1].title,substring=true);shot("11-chapter-two")
        ui.onNodeWithTag("novel.page").performTouchInput{click(center)};ui.onNodeWithTag("novel.menu.toc").performClick();ui.onNodeWithTag("novel.toc").performScrollToIndex(0);ui.onNodeWithTag("novel.chapter.0").performClick()
        ui.waitUntil(10000){JSONObject(prefs.getString("last","{}")!!).optInt("chapter",-1)==0}
        ui.onNodeWithTag("novel.page").performTouchInput{click(center)};ui.onNodeWithTag("novel.menu.font").performClick();ui.onNodeWithTag("novel.turn").performClick();ui.onNodeWithTag("novel.turn.scroll").performClick()
        ui.onNodeWithTag("novel.scroll").assertExists()
        ui.onNodeWithTag("novel.scroll").performTouchInput{click(center)}
        ui.onNodeWithTag("novel.scroll").performTouchInput{swipeUp()}
        ui.waitUntil(10000){offset()>100};shot("12-continuous-scroll")
        ui.onNodeWithTag("novel.scroll").performTouchInput{click(center)}
        ui.onNodeWithTag("novel.menu.font").performClick();ui.onNodeWithTag("novel.turn").performClick()
        ui.onNodeWithTag("novel.turn.slide").performClick();ui.onNodeWithTag("novel.page").assertExists()
        assertTrue("scroll-to-page keeps chapter character position",offset()>0)
        val savedOffset=offset()
        ui.onNodeWithTag("novel.reader.back").performClick();ui.onNodeWithTag("novel.detail.read").assertIsDisplayed()
        ui.onNodeWithTag("novel.detail.read").performClick()
        ui.waitUntil(10000){ui.onAllNodesWithTag("novel.page").fetchSemanticsNodes().isNotEmpty()}
        assertEquals("reader resume restores actual character position",savedOffset,offset());shot("14-resumed-position")
        ui.onNodeWithTag("novel.page").performTouchInput{click(center)};ui.onNodeWithTag("novel.reader.back").performClick()
        saveNovelEvidence("reader-android-verification.json",JSONObject().put("exactCollectionSha256","874efe33cbe38b7dcf830704b5bd0614b9485fe1974a20d9c09030ebec07df30").put("book",book.book.name).put("realTOC",book.chapters.size).put("networkAllowed",false).put("passed",true).toString(2).toByteArray())
    }
}
