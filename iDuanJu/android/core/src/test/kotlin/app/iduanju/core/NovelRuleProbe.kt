package app.iduanju.core

import app.iduanju.core.novel.*
import org.json.JSONArray
import java.io.File

/** Local diagnostic: executes a supplied rule with the production sandbox, never a JVM eval. */
object NovelRuleProbe {
    @JvmStatic fun main(args: Array<String>) {
        val source = NovelSource(JSONArray(File(args[0]).readText()).getJSONObject(args[1].toInt()))
        println(NovelSources.ruleValue("", "@js:" + File(args[2]).readText(), source, source.id))
    }
}
