package app.iduanju.core

import app.iduanju.core.novel.*
import org.json.JSONObject
import java.io.File

/** Debug helper: `NovelRuleDebug page.html listRule [fieldRule] [base]`. */
object NovelRuleDebug {
    @JvmStatic fun main(args: Array<String>) {
        // SOURCE=bundle.json:index uses a real source (jsLib, variables) instead of a blank one.
        val source = System.getenv("SOURCE")?.split(":")?.let { (f, i) -> NovelSource(org.json.JSONArray(File(f).readText()).getJSONObject(i.toInt())) }
            ?: NovelSource(JSONObject().put("bookSourceUrl", args.getOrElse(3) { "https://x.test" }).put("bookSourceName", "debug"))
        val html = File(args[0]).readText(); NovelScript.src.set(html)
        val list = NovelSources.nodes(org.jsoup.Jsoup.parse(html), args[1], source, args.getOrElse(3) { source.id })
        println("list ${list.size}")
        if (args.size > 2) list.firstOrNull()?.let { println("str " + NovelSources.ruleValue(it, args[2], source, source.id)) }
        System.exit(0)
    }
}
