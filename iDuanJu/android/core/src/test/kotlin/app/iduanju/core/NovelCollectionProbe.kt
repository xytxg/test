package app.iduanju.core

import app.iduanju.core.novel.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Bounded subprocess runner for the user-supplied collection; no source scripts are bundled. */
object NovelCollectionProbe {
    @JvmStatic fun main(args: Array<String>) {
        val raw = JSONArray(File(args[0]).readText())
        val source = NovelSource(raw.getJSONObject(args[1].toInt()))
        val report = JSONObject().put("index", args[1].toInt()).put("name", source.name)
        fun stage(name: String, block: () -> Int) {
            try { report.put(name, JSONObject().put("status", "ok").put("count", block())) }
            catch (e: Exception) { report.put(name, JSONObject().put("status", "failed").put("error", e.message.orEmpty().replace(Regex("https?://[^\\s]+"), "[source URL]").take(240))) }
        }
        var categories = emptyList<NovelCategory>()
        stage("categories") { categories = NovelSources.categories(source); categories.size }
        if (args.getOrNull(2) == "live") {
            var hits = emptyList<NovelHit>()
            categories.firstOrNull { it.url.isNotBlank() }?.let { cat -> stage("explore") {
                hits = NovelSources.search(source, "", category = cat)
                check(hits.isNotEmpty()) { "empty book list" }; hits.size
            } }
            var found = emptyList<NovelHit>()
            val keyword = if(source.name=="七猫小说") "都市" else source.rules("ruleSearch").optString("checkKeyWord").ifBlank { "西游记" }
            report.put("keyword",keyword)
            stage("search") { found = NovelSources.search(source, keyword); check(found.isNotEmpty()) { "empty search" }; found.size }
            (found.firstOrNull() ?: hits.firstOrNull())?.let { book ->
                report.put("bookTitle",book.name)
                var toc = emptyList<NovelChapter>()
                stage("toc") { toc = NovelSources.chapters(source, book.url); check(toc.isNotEmpty()) { "empty chapter list" }; toc.size }
                if(toc.isNotEmpty() && source.name in listOf("番茄小说","书旗小说")) {
                    val texts=mutableListOf<String>()
                    for(i in 0 until minOf(3,toc.size))stage("chapter${i+1}") {
                        val text=NovelSources.content(source,toc[i],toc.getOrNull(i+1)?.url,book.url)
                        check(text.length>300){"正文过短，不能记作阅读通过"};texts+=text;text.length
                    }
                    stage("offlineCache") {
                        check(texts.size==minOf(3,toc.size)){"前三章正文未全部通过"}
                        val root=java.nio.file.Files.createTempDirectory("novel-offline").toFile()
                        try {
                            val cache=NovelCache(root);cache.saveBook(source.id,book,toc)
                            texts.forEachIndexed{i,text->cache.save(source.id,book.url,toc[i].url,text)}
                            NovelSources.fixture={error("offline: network forbidden")}
                            texts.forEachIndexed{i,text->check(NovelCache(root).read(source.id,book.url,toc[i].url)==text)}
                            texts.size
                        } finally {NovelSources.fixture=null;root.deleteRecursively()}
                    }
                }
                if (toc.isNotEmpty()) stage("content") {
                    var last: Exception? = null
                    var body = ""
                    var chapter = toc.first()
                    for ((index, candidate) in toc.take(3).withIndex()) {
                        try {
                            val text = NovelSources.content(source,candidate,toc.getOrNull(index+1)?.url,book.url)
                            check(text.length > 80) { "body too short" }
                            body=text;chapter=candidate;report.put("contentChapterIndex",index);break
                        } catch (e: Exception) {last=e}
                    }
                    if(body.isBlank())throw last ?: IllegalStateException("no readable sample chapter")
                    val root = java.nio.file.Files.createTempDirectory("novel-probe").toFile()
                    try {
                        val cache = NovelCache(root)
                        cache.saveBook(source.id, book, toc); cache.save(source.id, book.url, chapter.url, body)
                        check(NovelCache(root).read(source.id, book.url, chapter.url) == body) { "offline cache mismatch" }
                        report.put("cachedSample", true)
                    } finally { root.deleteRecursively() }
                    body.length
                }
            }
        }
        println(report)
    }
}
