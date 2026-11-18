package app.iduanju.core

import app.iduanju.core.novel.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Explore-only probe for one source of a user-supplied collection: categories, then page 1 of up to N categories. */
object NovelRankProbe {
    @JvmStatic fun main(args: Array<String>) {
        val index = args[1].toInt()
        val source = NovelSource(JSONArray(File(args[0]).readText()).getJSONObject(index))
        val limit = args.getOrNull(2)?.toInt() ?: 3
        val report = JSONObject().put("index", index).put("name", source.name)
        try {
            val cats = NovelSources.categories(source)
            report.put("categories", cats.size)
            val out = JSONArray()
            if (System.getenv("RANK_DEBUG") == "1") cats.firstOrNull { it.url.isNotBlank() }?.let { c ->
                println("DEBUG url=" + c.url.take(200))
                println("DEBUG page=" + runCatching { NovelSources.page(c.url, source).text.take(400) }.getOrElse { "ERR " + it })
            }
            for (c in cats.filter { it.action == null && it.url.isNotBlank() }.take(limit)) {
                val t = System.currentTimeMillis()
                try {
                    val hits = NovelSources.search(source, "", category = c)
                    if (System.getenv("RECORD_DETAIL") == "1" && out.length() == 0) hits.firstOrNull()?.let { b ->
                        report.put("detail", runCatching { val toc = NovelSources.chapters(source, b.url); JSONObject().put("toc", toc.size).put("first", toc.firstOrNull()?.title ?: "").put("urls", toc.map { it.url }.toSet().size).put("firstURL", toc.firstOrNull()?.url ?: "") }
                            .getOrElse { JSONObject().put("error", (it.message ?: it.toString()).take(300)) })
                    }
                    out.put(JSONObject().put("title", c.title).put("count", hits.size).put("first", hits.firstOrNull()?.let { "${it.name}|${it.url}" } ?: "").put("ms", System.currentTimeMillis() - t))
                } catch (e: Throwable) { out.put(JSONObject().put("title", c.title).put("url", c.url.take(160)).put("error", (e.message ?: e.toString()).take(300))) }
            }
            report.put("explore", out)
        } catch (e: Throwable) { report.put("catError", (e.message ?: e.toString()).take(300)) }
        println(report)
        System.exit(0)
    }
}
