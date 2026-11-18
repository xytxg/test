package app.iduanju

import androidx.test.platform.app.InstrumentationRegistry
import app.iduanju.core.novel.*
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.io.File
import java.util.concurrent.TimeUnit

/** Actual Android ICU/Rhino and production network/cache, not only desktop JVM tests. */
class NovelLiveSourcesTest {
    @Test fun fanqieAndShuqiThreeChapterOfflineFlow() {
        NovelSources.fixture=null
        val http=OkHttpClient.Builder().callTimeout(45,TimeUnit.SECONDS).build()
        val collection=http.newCall(Request.Builder().url("https://www.yckceo.com/yuedu/shuyuans/json/id/1335.json").build()).execute().use {
            check(it.isSuccessful);it.body!!.string()
        }
        val sources=NovelSources.import(collection)
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val report=org.json.JSONArray()
        for(name in listOf("番茄小说","书旗小说")) {
            val source=sources.first{it.name==name}
            val categories=NovelSources.categories(source)
            val rank=NovelSources.search(source,"",category=categories.first{it.url.isNotBlank() && it.action==null})
            assertTrue("$name rank",rank.isNotEmpty())
            val hits=NovelSources.search(source,source.rules("ruleSearch").getString("checkKeyWord"))
            assertTrue("$name search",hits.isNotEmpty())
            val book=hits.first();val toc=NovelSources.chapters(source,book.url)
            assertTrue("$name toc",toc.size>3)
            val texts=(0..2).map{i->NovelSources.content(source,toc[i],toc.getOrNull(i+1)?.url,book.url).also{assertTrue("$name chapter $i",it.length>300)}}
            val root=File(context.cacheDir,"novel-live-"+java.util.UUID.randomUUID())
            try {
                val cache=NovelCache(root);cache.saveBook(source.id,book,toc)
                texts.forEachIndexed{i,text->cache.save(source.id,book.url,toc[i].url,text)}
                NovelSources.fixture={error("offline: no network")}
                texts.forEachIndexed{i,text->assertEquals(text,NovelCache(root).read(source.id,book.url,toc[i].url))}
            } finally {NovelSources.fixture=null;root.deleteRecursively()}
            report.put(JSONObject().put("name",name).put("categories",categories.size).put("rank",rank.size).put("search",hits.size).put("toc",toc.size)
                .put("chapterLengths",org.json.JSONArray(texts.map{it.length})).put("offlineCache",3))
        }
        val output=File(context.getExternalFilesDir(null),"novel-real-sources.json")
        output.writeText(report.toString(2))
        saveNovelEvidence(output.name,output.readBytes())
    }
}
