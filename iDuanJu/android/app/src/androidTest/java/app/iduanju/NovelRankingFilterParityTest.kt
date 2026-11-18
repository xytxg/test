package app.iduanju

import androidx.activity.enableEdgeToEdge
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import app.iduanju.core.novel.*
import app.iduanju.novel.NovelScreen
import app.iduanju.ui.theme.IdjTheme
import org.json.*
import org.junit.*
import org.junit.Assert.*

/** Real user source, real recorded public API responses, production native filter controls. No invented rank rows. */
class NovelRankingFilterParityTest {
    @get:Rule val ui=createAndroidComposeRule<androidx.activity.ComponentActivity>()
    @After fun cleanup(){NovelSources.fixture=null}
    @Test fun actualQimaoFiltersReloadSelectedCategoryWithNewRequest(){
        val ins=InstrumentationRegistry.getInstrumentation()
        fun asset(name:String)=ins.context.assets.open(name).bufferedReader().use{it.readText()}
        val raw=asset("real-1335.json")
        assertEquals("874efe33cbe38b7dcf830704b5bd0614b9485fe1974a20d9c09030ebec07df30",java.security.MessageDigest.getInstance("SHA-256").digest(raw.toByteArray()).joinToString(""){"%02x".format(it)})
        val source=NovelSources.import(raw).first{it.name=="七猫小说"}
        val ctx=ins.targetContext
        val prefs=ctx.getSharedPreferences("novel",0)
        prefs.edit().clear().putString("sources",raw).putString("rankSource",source.id).commit()
        fun stable(u:String)=java.net.URI(u).let{it.path+"?"+it.rawQuery.orEmpty().split('&').filterNot{it.startsWith("sign=")}.sorted().joinToString("&")}
        val routes=JSONArray(asset("legado-rank/source7-filter-routes.json"))
        val requests=java.util.concurrent.CopyOnWriteArrayList<String>()
        NovelSources.fixture={u->
            when{
                java.net.URI(u).path=="/api/v5/category/index"->asset("legado-rank/source7-category-index.json")
                java.net.URI(u).path=="/api/v1/leader-board"->asset("legado-rank/source7-rank-index.json")
                else->{
                    val r=(0 until routes.length()).map{routes.getJSONObject(it)}.firstOrNull{stable(it.getString("url"))==stable(u)}?:error("unrecorded actual filter request: $u")
                    requests.add(u);asset("legado-rank/"+r.getString("file"))
                }
            }
        }
        // Use an isolated persistent source-state root, then restore the installation's actual root.
        NovelSources.configureStorage(java.io.File(ctx.cacheDir,"novel-filter-qa-"+java.util.UUID.randomUUID()))
        try{
            NovelSources.categoryAction(source,NovelCategory("reset","",action="source.setVariable('{}')",type="button"))
            val initial=NovelSources.categories(source)
            val bar=initial.first{it.title.startsWith("⚙ 筛选")}
            val expected=(0 until routes.length()).map{n->NovelSources.search(source,"",1,NovelCategory("recorded",routes.getJSONObject(n).getString("url"))).first().name}
            requests.clear()
            ui.runOnUiThread{ui.activity.enableEdgeToEdge()};ui.setContent{IdjTheme(dark=false){NovelScreen({})}}
            ui.onNodeWithText("排行榜").performClick()
            ui.waitUntil(10000){ui.onAllNodesWithTag("novel.filter."+bar.title).fetchSemanticsNodes().isNotEmpty()}
            ui.onNodeWithTag("novel.filter."+bar.title).performScrollTo().performClick()
            ui.waitUntil(10000){requests.size>=1&&ui.onAllNodesWithText(expected[0],substring=false).fetchSemanticsNodes().isNotEmpty()}
            for((n,title) in listOf("完结","50-100万","按评分").withIndex()){
                ui.onNodeWithText(title,substring=false).performScrollTo().performClick()
                ui.waitUntil(10000){requests.size>=n+2&&ui.onAllNodesWithText(expected[n+1],substring=false).fetchSemanticsNodes().isNotEmpty()}
                ui.onNodeWithText("● "+title,substring=false).assertExists()
            }
            assertEquals(4,requests.size)
            assertTrue(requests.last().contains("over=1"));assertTrue(requests.last().contains("words=2"));assertTrue(requests.last().contains("sort=2"));assertTrue(requests.last().contains("page=1"))
            ui.waitForIdle();val b=ins.uiAutomation.takeScreenshot();try{val out=java.io.ByteArrayOutputStream();b.compress(android.graphics.Bitmap.CompressFormat.PNG,100,out);saveNovelEvidence("ranking-android-real-filter-controls.png",out.toByteArray())}finally{b.recycle()}
        }finally{NovelSources.configureStorage(ctx.filesDir);NovelSources.fixture=null}
    }
}
