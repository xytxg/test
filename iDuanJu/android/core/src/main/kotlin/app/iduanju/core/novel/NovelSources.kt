package app.iduanju.core.novel

import app.iduanju.core.util.NetGuard
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import org.jsoup.Jsoup
import org.jsoup.nodes.Element
import java.net.URI
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

data class NovelSource(val json: JSONObject) {
    val id: String get() = json.optString("bookSourceUrl")
    val name: String get() = json.optString("bookSourceName", id)
    val enabled: Boolean get() = json.optBoolean("enabled", true)
    fun rules(name: String): JSONObject = json.optJSONObject(name)
        ?: runCatching { JSONObject(json.optString(name)) }.getOrDefault(JSONObject())
}
data class NovelHit(val name: String, val author: String, val url: String, val cover: String = "", val kind: String = "", val latest: String = "")
data class NovelFlexStyle(val basis:Double=-1.0,val grow:Double=0.0,val wrapBefore:Boolean=false)
data class NovelCategory(val title: String, val url: String, val group: String = "推荐", val action: String? = null,
    val type:String="url",val chars:List<String> = emptyList(),val defaultValue:String="",val viewName:String="",
    val style:NovelFlexStyle=NovelFlexStyle(),val value:String="",val displayTitle:String=title) {
    val selectionKey get() = "$group|$title|$type"
    val id get() = "$selectionKey|$url|${action.orEmpty()}"
    val isControl get() = type != "url"
}
data class NovelChapter(val title: String, val url: String)

/** Text-source subset of Legado: CSS/Jsoup rules, simple JSON paths, GET/POST and discovery. */
object NovelSources {
    fun configureStorage(root: java.io.File) { NovelScript.configure(root) }
    const val userAgent = "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"
    private val http = OkHttpClient.Builder().callTimeout(20, TimeUnit.SECONDS).followRedirects(false).build()
    @Volatile var fixture: ((String) -> String)? = null

    fun import(text: String): List<NovelSource> {
        val trimmed = text.trim().removePrefix("\uFEFF")
        val array = if (trimmed.startsWith("[")) JSONArray(trimmed) else JSONArray().put(JSONObject(trimmed))
        return (0 until array.length()).mapNotNull { i -> array.optJSONObject(i)?.let { o ->
            if (o.optInt("bookSourceType", 0) != 0 || o.optString("bookSourceUrl").isBlank()) null else NovelSource(o)
        } }.distinctBy { it.id }
    }

    fun absolute(raw: String, base: String): String {
        if (raw.isBlank()) return ""
        val parts = raw.trim().split(Regex(",\\s*(?=\\{)"), limit = 2)
        val baseURL = base.split(Regex(",\\s*(?=\\{)"), limit = 2)[0].substringBefore('#')
        return URI(baseURL).resolve(parts[0].replace(" ", "%20")).toString() + if(parts.size == 2) "," + parts[1] else ""
    }

    private fun script(code: String) = code.trim().removePrefix("@js:").removePrefix("<js>").removeSuffix("</js>")
    private fun template(raw: String, source: NovelSource, key: String, page: Int, charset: String): String {
        var text = raw
        // Balanced templates may contain nested object literals or braces inside strings.
        var at = 0
        while (true) {
            val start = text.indexOf("{{", at); if(start < 0) break
            var i = start + 2; var depth = 0; var quote: Char? = null
            while(i < text.length - 1) {
                val ch = text[i]
                if(quote != null) { if(ch == '\\') i++ else if(ch == quote) quote = null }
                else if(ch in "\"'`") quote = ch
                else if(ch == '{') depth++
                else if(ch == '}') { if(depth == 0 && text[i + 1] == '}') break; depth-- }
                i++
            }
            require(i < text.length - 1) { "网址模板没有结束" }
            val expr = text.substring(start + 2, i).trim()
            val value = when(expr) { "key" -> URLEncoder.encode(key, charset); "page" -> page.toString()
                else -> NovelScript(source, source.id, key, page).eval(expr)?.toString().orEmpty() }
            text = text.substring(0,start) + value + text.substring(i+2); at = start + value.length
        }
        return Regex("<([^<>]*,[^<>]*)>").replace(text) { m -> m.groupValues[1].split(',').let { it[minOf(page-1,it.lastIndex).coerceAtLeast(0)] } }
    }

    data class PageResponse(val text: String, val url: String, val headers: Map<String,String> = emptyMap())
    data class ByteResponse(val bytes: ByteArray, val status: Int, val headers: Map<String,String>)

    /** Private / loopback / link-local targets stay blocked; public IP literals are normal for mirror-line sources. */
    private fun blockedHost(host: String) = if (NetGuard.isIPLiteral(host)) NetGuard.isBlockedIP(host.trim('[', ']')) else NetGuard.resolvesToBlocked(host)

    internal fun fetchBytes(url: String, method: String, headers: JSONObject?, body: ByteArray): ByteResponse {
        var address = url; var verb = method.uppercase()
        require(verb in listOf("GET","POST")) { "书源 HTTP 方法不支持" }
        require(body.size<=16*1024*1024) { "书源请求过大" }
        val originalHost=URI(address).host
        repeat(6) {
            val uri=URI(address)
            require(uri.scheme in listOf("https","http") && !uri.host.isNullOrEmpty() && !blockedHost(uri.host)) { "书源地址无效或指向内网" }
            val req=Request.Builder().url(address).header("User-Agent",userAgent)
            if(uri.host==originalHost)headers?.let { for(k in it.keys())req.header(k,it.getString(k)) }
            if(verb=="POST")req.post(body.toRequestBody((headers?.optString("Content-Type")?.takeIf{it.isNotBlank()} ?: "application/octet-stream").toMediaType()))
            http.newCall(req.build()).execute().use { response ->
                if(response.isRedirect) {
                    address=absolute(response.header("Location") ?: error("书源跳转缺少地址"),address)
                    if(response.code in listOf(301,302,303))verb="GET"
                } else {
                    val out=java.io.ByteArrayOutputStream()
                    response.body?.byteStream()?.use { stream ->
                        val buffer=ByteArray(8192)
                        while(true){val n=stream.read(buffer);if(n<0)break;require(out.size()+n<=8*1024*1024){"书源响应过大"};out.write(buffer,0,n)}
                    }
                    return ByteResponse(out.toByteArray(),response.code,response.headers.names().associateWith{response.header(it).orEmpty()})
                }
            }
        }
        error("书源跳转次数过多")
    }

    fun fetch(raw: String, source: NovelSource, key: String = "", page: Int = 1): String = fetchResponse(raw,source,key,page).text

    fun fetchResponse(raw: String, source: NovelSource, key: String = "", page: Int = 1): PageResponse {
        var rule = raw.trim()
        if(rule.startsWith("@js:") || rule.startsWith("<js>")) rule = NovelScript(source,source.id,key,page).eval(script(rule))?.toString().orEmpty()
        rule = template(rule,source,key,page,"UTF-8")
        val pieces = rule.split(Regex(",\\s*(?=\\{)"), limit = 2)
        val options = if (pieces.size == 2) JSONObject(pieces[1]) else JSONObject()
        val explicitCharset = options.optString("charset").takeIf { it.isNotBlank() && it != "null" }
        val charset = explicitCharset ?: "UTF-8"
        fun fill(s: String) = template(s,source,key,page,charset)
        var address = absolute(fill(pieces[0]), source.id)
        if(address.startsWith("data:")) {
            val data = address.substringAfter(',')
            val bytes = if(address.substringBefore(',').endsWith(";base64")) java.util.Base64.getDecoder().decode(data) else java.net.URLDecoder.decode(data.replace("+","%2B"),"UTF-8").toByteArray()
            return PageResponse(if(options.optString("type").isNotBlank())bytes.joinToString(""){"%02x".format(it)} else String(bytes),address)
        }
        fixturePage?.let { return it(address) }
        fixture?.let { return PageResponse(it(address),address) }
        val headers = headers(source)
        val originalHost = URI(address).host
        repeat(6) {
            val uri = URI(address)
            require(uri.scheme in listOf("https", "http") && !uri.host.isNullOrEmpty() && !blockedHost(uri.host)) { "书源地址无效或指向内网" }
            val req = Request.Builder().url(address).header("User-Agent", userAgent)
            if (uri.host == originalHost) for (name in headers.keys()) req.header(name, headers.getString(name))
            if (uri.host == originalHost) options.optJSONObject("headers")?.let { extra -> for(name in extra.keys()) req.header(name,extra.get(name).toString()) }
            if (it == 0 && options.optString("method").equals("POST", true)) {
                val body = fill(options.optString("body"))
                val ct = if(body.trimStart().startsWith('{')) "application/json; charset=utf-8" else "application/x-www-form-urlencoded; charset=$charset"
                req.post(body.toRequestBody(ct.toMediaType()))
            }
            http.newCall(req.build()).execute().use { response ->
                if (response.isRedirect) {
                    address = absolute(response.header("Location") ?: error("书源跳转缺少地址"), address)
                } else {
                    check(response.isSuccessful) { "书源 HTTP ${response.code}" }
                    val bytes = response.body?.byteStream()?.use { stream ->
                        val out = java.io.ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) { val n = stream.read(buffer); if (n < 0) break; require(out.size() + n <= 8 * 1024 * 1024) { "书源页面过大" }; out.write(buffer, 0, n) }
                        out.toByteArray()
                    } ?: error("书源空响应")
                    val text = if(options.optString("type").isNotBlank())bytes.joinToString(""){"%02x".format(it)} else decode(bytes, explicitCharset, response.header("Content-Type"))
                    return PageResponse(text,address,response.headers.names().associateWith { response.header(it).orEmpty() })
                }
            }
        }
        error("书源跳转次数过多")
    }

    /** Same order as iOS LegadoHTTP.decode: source option > Content-Type > <meta charset> > UTF-8 (GB18030 if UTF-8 is invalid). */
    internal var fixturePage: ((String) -> PageResponse)? = null

    internal fun decode(bytes: ByteArray, explicit: String?, contentType: String?): String {
        fun cs(name: String?) = name?.trim()?.trim('"', '\'')?.takeIf { it.isNotEmpty() }?.let { runCatching { java.nio.charset.Charset.forName(it) }.getOrNull() }
        cs(explicit)?.let { return String(bytes, it) }
        cs(contentType?.let { Regex("(?i)charset=([\\w-]+)").find(it)?.groupValues?.get(1) })?.let { return String(bytes, it) }
        val head = String(bytes, 0, minOf(bytes.size, 4096), Charsets.ISO_8859_1)
        cs(Regex("(?i)<meta[^>]+charset\\s*=\\s*[\"']?([\\w-]+)").find(head)?.groupValues?.get(1))?.let { return String(bytes, it) }
        val decoder = Charsets.UTF_8.newDecoder()
        return try { decoder.decode(java.nio.ByteBuffer.wrap(bytes)).toString() } catch (_: java.nio.charset.CharacterCodingException) { String(bytes, java.nio.charset.Charset.forName("GB18030")) }
    }

    fun categories(source: NovelSource): List<NovelCategory> {
        var raw = source.json.optString("exploreUrl").trim()
        if (raw.isEmpty()) return emptyList()
        if(raw.startsWith("@js:") || raw.startsWith("<js>")) raw = NovelScript(source,source.id).eval(script(raw))?.toString().orEmpty()
        val parsed = parseCategories(raw)
        val initial = NovelScript.exploreInfo(source.id)
        val info = JSONObject(initial.toString())
        var changed = false
        parsed.filter { it.isControl }.forEach { c -> if (!info.has(c.title)) { info.put(c.title, c.defaultValue.ifEmpty { c.chars.firstOrNull().orEmpty() }); changed = true } }
        if (changed) NovelScript.mergeExploreInfo(source.id,initial,info)
        return parsed.map { c ->
            val display = if (c.viewName.isBlank()) c.title else runCatching{NovelScript(source,source.id).eval(script(c.viewName))?.toString()}.getOrNull() ?: c.title
            c.copy(value=info.optString(c.title),displayTitle=display)
        }
    }

    fun categoryAction(source: NovelSource, category: NovelCategory, value:String? = null) {
        if (category.isControl) {
            val initial = NovelScript.exploreInfo(source.id)
            val info = JSONObject(initial.toString())
            val next = value ?: if (category.type == "toggle" && category.chars.isNotEmpty()) category.chars[(category.chars.indexOf(info.optString(category.title)) + 1).mod(category.chars.size)] else null
            if (next != null) { info.put(category.title,next); NovelScript.mergeExploreInfo(source.id,initial,info) }
        }
        category.action?.takeIf { it.isNotBlank() }?.let { NovelScript(source,source.id).eval(script(it)) }
    }

    /** Titles/groups identify a category across filter-generated URL changes; never keep a stale URL snapshot. */
    fun refreshedCategory(previous:NovelCategory?, categories:List<NovelCategory>, group:String):NovelCategory? =
        categories.firstOrNull { !it.isControl && it.selectionKey==previous?.selectionKey }
            ?: categories.firstOrNull { !it.isControl && it.url==previous?.url }
            ?: categories.firstOrNull { !it.isControl && it.group==group }
            ?: categories.firstOrNull { !it.isControl }


    /** Legado parses discovery JSON with Gson, which tolerates raw line breaks / tabs inside strings (multi-line `@js:` urls). */
    internal fun escapeRawControls(raw: String): String {
        val out = StringBuilder(); var inString = false; var escaped = false
        for (c in raw) {
            if (inString) {
                if (escaped) { escaped = false; out.append(c); continue }
                when (c) { '\\' -> { escaped = true; out.append(c) }; '"' -> { inString = false; out.append(c) }
                    '\n' -> out.append("\\n"); '\r' -> out.append("\\r"); '\t' -> out.append("\\t"); else -> out.append(c) }
            } else { if (c == '"') inString = true; out.append(c) }
        }
        return out.toString()
    }

    fun parseCategories(raw: String): List<NovelCategory> {
        var group = "推荐"
        val out = arrayListOf<NovelCategory>()
        fun add(title: String, url: String, action: String? = null) {
            val t = stripInvisible(title).trim(); val u = url.trim(); if(t.isEmpty())return
            if(!action.isNullOrBlank())out += NovelCategory(t,"",group,action)
            else if(u.isBlank())group=t
            else out += NovelCategory(t,u,group)
        }
        if (raw.startsWith("[")) {
            val a = runCatching { JSONArray(raw) }.getOrElse { JSONArray(escapeRawControls(raw)) }
            for(i in 0 until a.length()) a.optJSONObject(i)?.let { o ->
                val type=o.optString("type").ifEmpty { "url" }
                if(type in listOf("button","text","toggle","select")) {
                    val title=stripInvisible(o.optString("title")).trim()
                    val chars=o.optJSONArray("chars")?.let { a -> (0 until a.length()).map { a.optString(it) } }.orEmpty()
                    val style=o.optJSONObject("style")
                    if(title.isNotEmpty())out += NovelCategory(title,"",group,o.optString("action").takeIf { it.isNotBlank() },type,chars,o.optString("default"),o.optString("viewName"),NovelFlexStyle(style?.optDouble("layout_flexBasisPercent",-1.0)?:-1.0,style?.optDouble("layout_flexGrow",0.0)?:0.0,style?.optBoolean("layout_wrapBefore",false)?:false))
                } else add(o.optString("title"),o.optString("url").takeUnless { it=="null" }.orEmpty())
            }
        } else for(line in raw.split("&&","\n").filter { it.isNotBlank() }) {
            val p=line.trim().split("::",limit=2)
            if(p.size==2)add(p[0],p[1])
            else if(p[0].startsWith("http")||p[0].startsWith('/'))add("推荐",p[0]) else group=p[0]
        }
        return out.distinctBy { it.id }
    }

    /** JSONPath subset used by sources: `$.a.b`, `a.b` (implicit `$.`), `$..deep`, `[*]`, `[0]`, `[-1]`, `[0,2]`, `[1:3]`, `['k']`. */
    internal fun jsonNodes(value: Any, raw: String): List<Any> {
        var path = raw.trim()
        if (path.startsWith("@json:", ignoreCase = true)) path = path.substring(6).trim()
        if (path.startsWith("$")) path = path.substring(1)
        fun children(n: Any): List<Any> = when (n) {
            is JSONObject -> n.keys().asSequence().map { n.get(it) }.toList()
            is JSONArray -> (0 until n.length()).map { n.get(it) }
            else -> emptyList()
        }
        fun deep(n: Any): List<Any> = listOf(n) + children(n).flatMap { deep(it) }
        fun member(n: Any, name: String): List<Any> = when {
            name == "*" -> children(n)
            n is JSONObject -> n.opt(name)?.takeIf { it != JSONObject.NULL }?.let { listOf(it) }.orEmpty()
            else -> emptyList()
        }
        fun name(at: Int): Pair<String, Int> { var j = at; while (j < path.length && path[j] != '.' && path[j] != '[') j++; return path.substring(at, j).trim() to j }
        var current = listOf(value); var i = 0
        while (i < path.length) {
            when {
                path.startsWith("..", i) -> { val (n, next) = name(i + 2); i = next; current = current.flatMap { deep(it) }.let { all -> if (n.isEmpty()) all else all.flatMap { member(it, n) } } }
                path[i] == '.' -> { val (n, next) = name(i + 1); i = next; if (n.isNotEmpty()) current = current.flatMap { member(it, n) } }
                path[i] == '[' -> {
                    val close = path.indexOf(']', i).takeIf { it > i } ?: path.length
                    val inner = path.substring(i + 1, close).trim(); i = close + 1
                    current = current.flatMap { n -> when {
                        inner == "*" -> children(n)
                        inner.startsWith("'") || inner.startsWith("\"") -> inner.split(',').flatMap { member(n, it.trim().trim('\'', '"')) }
                        n is JSONArray && !inner.startsWith("?") -> pick(children(n), inner)
                        else -> emptyList()
                    } }
                }
                else -> { val (n, next) = name(i); i = next; if (n.isNotEmpty()) current = current.flatMap { member(it, n) } }
            }
        }
        return current.filter { it != JSONObject.NULL }
    }

    /** `{$.path}` placeholders inside a JSON rule (`/book?id={$.id}`). */
    private fun jsonTemplate(content: Any, rule: String) = Regex("\\{(\\$\\.[^{}]+)\\}").replace(rule) { m -> jsonNodes(content, m.groupValues[1]).joinToString(",") }

    /** Legado index suffix of one rule segment: `a.0`, `.item.1:3`, `li!0`, `tag.p.-1`, `div[0,2]`. */
    internal fun splitIndex(seg: String): Pair<String, String?> {
        val body = seg.trim()
        if (body.endsWith("]")) {
            val open = body.lastIndexOf('[')
            val inner = if (open >= 0) body.substring(open + 1, body.length - 1) else ""
            if (inner.isNotBlank() && inner.all { it in "0123456789-:,! " }) return body.substring(0, open) to inner.trim()
        }
        var i = body.length
        while (i > 0 && body[i - 1] in "0123456789-:, ") i--
        if (i == body.length || i <= 1 || body.substring(i).none { it.isDigit() }) return body to null
        val mark = body[i - 1]
        if (mark != '.' && mark != '!') return body to null
        return body.substring(0, i - 1) to ((if (mark == '!') "!" else "") + body.substring(i).trim())
    }

    /** Legado indexes: `0`, `-1`, `1,3`, `1:3` (inclusive), `!0` (exclude). */
    internal fun <T> pick(items: List<T>, spec: String?): List<T> {
        var s = spec?.trim().orEmpty(); if (s.isEmpty()) return items
        val exclude = s.startsWith("!"); if (exclude) s = s.substring(1)
        val n = items.size; val idx = arrayListOf<Int>()
        for (part in s.split(',')) {
            val p = part.split(':').map { it.trim().toIntOrNull() }
            if (p.size >= 2) {
                var a = p[0] ?: 0; var b = p[1] ?: (n - 1)
                if (a < 0) a += n; if (b < 0) b += n
                val lo = maxOf(0, minOf(a, b)); val hi = minOf(n - 1, maxOf(a, b))
                if (lo <= hi) idx += if (a <= b) (lo..hi).toList() else (hi downTo lo).toList()
            } else p[0]?.let { idx += if (it < 0) n + it else it }
        }
        val valid = idx.filter { it in 0 until n }
        return if (exclude) items.filterIndexed { i, _ -> i !in valid.toSet() } else valid.map { items[it] }
    }

    private fun select(root: Element, rule: String): List<Element> {
        if (rule.isBlank()) return listOf(root)
        var current = listOf(root)
        for (part in rule.removePrefix("@css:").split('@').filter { it.isNotBlank() }) {
            val (selector, index) = splitIndex(part)
            current = current.flatMap { el ->
                val found: List<Element> = when {
                    selector == "children" -> el.children().toList()
                    selector.startsWith("class.") -> selector.removePrefix("class.").trim().split(Regex("\\s+")).let { want -> el.allElements.filter { e -> want.all { e.hasClass(it) } } }
                    selector.startsWith("id.") -> el.allElements.filter { it.id() == selector.removePrefix("id.") }
                    selector.startsWith("tag.") -> el.getElementsByTag(selector.removePrefix("tag.")).toList()
                    selector.startsWith("text.") -> el.getElementsContainingOwnText(selector.removePrefix("text.")).toList()
                    else -> el.select(selector).toList()
                }
                pick(found, index)
            }
        }
        return current
    }

    /** `a&&b` concatenates, `a%%b` interleaves, `a||b` takes the first non-empty (outside quotes / brackets). */
    private fun splitTop(rule: String): Pair<List<String>, String> {
        for (op in listOf("&&", "||", "%%")) {
            val parts = arrayListOf<String>(); val cur = StringBuilder(); var depth = 0; var quote: Char? = null; var i = 0
            while (i < rule.length) {
                val c = rule[i]
                if (quote != null) { cur.append(c); if (c == quote) quote = null; i++; continue }
                if (c == '\'' || c == '"') quote = c
                if (c in "[({") depth++ else if (c in "])}") depth--
                if (depth == 0 && rule.startsWith(op, i)) { parts += cur.toString(); cur.clear(); i += 2; continue }
                cur.append(c); i++
            }
            parts += cur.toString()
            if (parts.size > 1) return parts.map { it.trim() }.filter { it.isNotEmpty() } to op
        }
        return listOf(rule) to ""
    }

    /** Splits a rule into selector and `<js>…</js>` / `@js:…` steps (Legado runs them left to right). */
    internal fun jsSegments(rule: String): List<Pair<Boolean, String>> {
        val out = arrayListOf<Pair<Boolean, String>>(); var rest = rule
        while (rest.isNotEmpty()) {
            val tag = rest.indexOf("<js>", ignoreCase = true); val at = rest.indexOf("@js:", ignoreCase = true)
            val i = listOf(tag, at).filter { it >= 0 }.minOrNull()
            if (i == null) { rest.trim().takeIf { it.isNotEmpty() }?.let { out += false to it }; break }
            rest.substring(0, i).trim().takeIf { it.isNotEmpty() }?.let { out += false to it }
            if (i == tag) {
                val close = rest.indexOf("</js>", i, ignoreCase = true)
                out += true to (if (close < 0) rest.substring(i + 4) else rest.substring(i + 4, close))
                rest = if (close < 0) "" else rest.substring(close + 5)
            } else { out += true to rest.substring(i + 4); rest = "" }
        }
        return out
    }

    internal fun nodes(content: Any, raw0: String, source: NovelSource, base: String, key: String = "", page: Int = 1): List<Any> {
        // `-` reverses the list; `+` (explicit no-reverse) is a no-op.
        val raw = raw0.trim().removePrefix("+")
        val segments = jsSegments(raw.removePrefix("-"))
        if (segments.any { it.first }) {
            var cur: Any? = content
            for ((js, part) in segments) {
                cur = if (js) {
                    val input: Any? = if (cur is List<*> && cur.all { it is Element }) cur else if (cur is List<*>) JSONArray(cur.map { if (it is Element) it.outerHtml() else it }) else cur?.toString()
                    val value = NovelScript(source, base, key, page).also { it.srcText = srcOf(content) }.eval(part, input)
                    if (value is String && value.trimStart().startsWith('[')) runCatching { JSONArray(value) }.getOrDefault(value) else value
                } else when (val c = cur) {
                    is List<*> -> c.filterNotNull().flatMap { nodes(it, part, source, base, key, page) }
                    is JSONArray -> (0 until c.length()).flatMap { val v = c.get(it); nodes(if (v is String) document(v) else v, part, source, base, key, page) }
                    is String -> nodes(document(c), part, source, base, key, page)
                    null -> emptyList()
                    else -> nodes(c, part, source, base, key, page)
                }
            }
            val list: List<Any> = when (val c = cur) {
                is List<*> -> c.filterNotNull()
                is JSONArray -> (0 until c.length()).map { val v = c.get(it); if (v is String) item(v) else v }
                null -> emptyList()
                else -> listOf(c)
            }
            return if (raw.startsWith('-')) list.reversed() else list
        }
        val reverse = raw.startsWith('-'); val rule = raw.removePrefix("-")
        val root=content as? Element ?: Jsoup.parse(content.toString())
        fun single(r: String): List<Any> = if (r.startsWith('$') || r.startsWith("@json:", true) || content is JSONObject || content is JSONArray) jsonNodes(content, r).flatMap { if(it is JSONArray)(0 until it.length()).map{n->it.get(n)} else listOf(it) }
            else if(r.startsWith("//") || r.startsWith("/") || r.startsWith("@xpath:", true)) root.selectXpath(scopedXPath(content, r.replace(Regex("^@xpath:", RegexOption.IGNORE_CASE), ""))).toList()
            else select(root, r)
        val result = splitTop(rule).let { (parts, op) -> when (op) {
                "||" -> parts.asSequence().map { single(it) }.firstOrNull { it.isNotEmpty() } ?: emptyList()
                "&&" -> parts.flatMap { single(it) }
                "%%" -> parts.map { single(it) }.let { lists -> (0 until (lists.maxOfOrNull { it.size } ?: 0)).flatMap { i -> lists.mapNotNull { it.getOrNull(i) } } }
                else -> single(rule)
            } }
        return if (reverse) result.reversed() else result
    }

    internal fun ruleValue(content: Any, raw: String, source: NovelSource, base: String, key: String = "", page: Int = 1): String {
        if (raw.isEmpty()) return ""
        val put = Regex("@put:(\\{[^}]*\\})").find(raw)
        if (put != null) {
            val vars=JSONObject(put.groupValues[1])
            for(k in vars.keys()) NovelScript.setVariable(source.id,k,ruleValue(content,vars.getString(k),source,base,key,page))
            return ruleValue(content,raw.removeRange(put.range),source,base,key,page)
        }
        val jsAt = raw.indexOf("@js:").takeIf{it>=0} ?: raw.indexOf("<js>")
        if(jsAt>=0) {
            val prefix=raw.substring(0,jsAt)
            // Legado hands a leading `@js:` the item itself (a JSON item stays an object, so `result.bookId` works).
            val input:Any=if(prefix.isBlank()) (if(content is JSONObject || content is JSONArray) content else content.toString()) else ruleValue(content,prefix,source,base,key,page)
            val code=Regex("\\{\\{(.*?)\\}\\}",RegexOption.DOT_MATCHES_ALL).replace(script(raw.substring(jsAt))) { m ->
                ruleValue(content,m.groupValues[1],source,base,key,page).replace("\\","\\\\").replace("'","\\'").replace("\"","\\\"").replace("\n","\\n")
            }
            return NovelScript(source,base,key,page).also { it.srcText = srcOf(content) }.eval(code,input)?.toString().orEmpty()
        }
        if(raw.contains("{{"))return Regex("\\{\\{(.*?)\\}\\}",RegexOption.DOT_MATCHES_ALL).replace(raw){m ->
            val expr=m.groupValues[1];if(expr.startsWith('$')||expr.startsWith('@'))ruleValue(content,expr,source,base,key,page)
            else NovelScript(source,base,key,page).also { it.srcText = srcOf(content) }.eval(expr,content.toString())?.toString().orEmpty()
        }
        if(raw.contains("||")) return raw.split("||").asSequence().map{ruleValue(content,it,source,base,key,page)}.firstOrNull{it.isNotBlank()}.orEmpty()
        if(raw.contains("&&")) return raw.split("&&").map{ruleValue(content,it,source,base,key,page)}.filter{it.isNotBlank()}.joinToString("\n")
        val parts = raw.split("##")
        val rule = parts[0]
        val json = content is JSONObject || content is JSONArray
        var text = if (rule.contains("{$.") && (json || content is String)) jsonTemplate(if(content is String)document(content) else content, rule)
        else if (rule.startsWith('$') || rule.startsWith("@json:", true) || json) jsonNodes(if(content is String)document(content) else content, rule).joinToString("\n") else if (rule.startsWith("http://") || rule.startsWith("https://")) rule
        else if(rule.startsWith('/') || rule.startsWith("@xpath:", true)) {
            val root=content as? Element ?: Jsoup.parse(content.toString())
            val w3c=org.jsoup.helper.W3CDom().namespaceAware(false); val doc=w3c.fromJsoup(root)
            val xpath=javax.xml.xpath.XPathFactory.newInstance().newXPath()
            val item = root !is org.jsoup.nodes.Document
            xpath.evaluate(scopedXPath(root, rule.replace(Regex("^@xpath:", RegexOption.IGNORE_CASE), "")), if(item) w3c.contextNode(doc) else doc, javax.xml.xpath.XPathConstants.NODESET).let { list ->
                val ns=list as org.w3c.dom.NodeList;(0 until ns.length).joinToString("\n"){ns.item(it).textContent}
            }
        } else if(rule in listOf("text","ownText","html","href","src","value")) {
            val root=content as? Element ?: Jsoup.parse(content.toString());when(rule){"ownText"->root.ownText();"html"->root.html();"text"->root.text();else->root.attr(rule)}
        } else {
            val at = rule.lastIndexOf('@')
            val attr = if (at >= 0) rule.substring(at + 1).trim() else "text"
            val selector = if (at >= 0) rule.substring(0, at).trim() else rule.trim()
            val root = content as? Element ?: Jsoup.parse(content.toString())
            // `@href` with no selector reads the current element.
            (if (selector.isEmpty()) listOf(root) else select(root, selector)).joinToString("\n") { el -> when (attr) { "text" -> el.text(); "html" -> el.html(); "ownText" -> el.ownText(); else -> el.attr(attr) } }
        }
        if (parts.size >= 2) {
            val regex=Regex(parts[1]); val replacement=parts.getOrElse(2){""}
            text = if(raw.endsWith("###"))regex.find(text)?.let { regex.replace(it.value,replacement) }.orEmpty() else regex.replace(text,replacement)
        }
        return text.trim()
    }

    private fun document(text: String): Any = when {
        text.trimStart().startsWith('{') -> JSONObject(text)
        text.trimStart().startsWith('[') -> JSONArray(text)
        Regex("<[A-Za-z!/]").containsMatchIn(text) -> Jsoup.parse(text)
        else -> text
    }

    /** Legado (JsoupXpath) roots an item rule at the item: `/a/@href` is its child link, `//p` stays inside it. */
    private fun scopedXPath(content: Any, rule: String) = if (content is Element && content !is org.jsoup.nodes.Document && rule.startsWith("/")) ".$rule" else rule

    /** Zero-width / soft-hyphen characters some sources sprinkle into titles to dodge keyword filters. */
    internal fun stripInvisible(text: String) = text.replace(Regex("[\\u00AD\\u200B-\\u200F\\u2060\\uFEFF]"), "")

    /** Main page request + the source's `loginCheckJs`, which Legado runs on every search / explore / detail / toc /
     *  content response and which may rewrite the body (decrypting APIs return `new StrResponse(url, decrypt(body))`). */
    internal fun page(raw: String, source: NovelSource, key: String = "", page: Int = 1): PageResponse {
        val response = fetchResponse(raw, source, key, page)
        NovelScript.src.set(response.text)
        val check = source.json.optString("loginCheckJs").trim().takeIf { it.isNotEmpty() && it != "null" } ?: return response
        val code = "result = __strResponse(result);\n" + script(check)
        val value = NovelScript(source, response.url, key, page).eval(code, JSONObject().put("url", response.url).put("body", response.text).put("code", 200))
        val body = (value as? JSONObject)?.optString("__body")?.takeIf { (value as JSONObject).has("__body") } ?: (value as? String)?.takeIf { it.isNotEmpty() }
        return (if (body == null) response else response.copy(text = body)).also { NovelScript.src.set(it.text) }
    }

    /** Source `header`: a JSON object, or (Legado) `@js:` / `<js>` code evaluated per request that returns one. */
    internal fun headers(source: NovelSource): JSONObject {
        source.json.optJSONObject("header")?.let { return it }
        val raw = source.json.optString("header").trim()
        if (raw.isEmpty() || raw == "null") return JSONObject()
        val text = if (raw.startsWith("@js:") || raw.startsWith("<js>")) runCatching { NovelScript(source, source.id).eval(script(raw))?.toString().orEmpty() }.getOrDefault("") else raw
        return runCatching { JSONObject(text) }.getOrDefault(JSONObject())
    }

    /** Legado's JS `src` is the analyzer's content: the item's HTML / JSON for item rules, the raw body for the page. */
    internal fun srcOf(content: Any?): String? = when (content) {
        is org.jsoup.nodes.Document -> null
        is Element -> content.outerHtml()
        is JSONObject, is JSONArray, is String -> content.toString()
        else -> null
    }

    /** A list item a script returned as HTML: one element (`<a href=…>`) stays that element, so `href` / `text` read it. */
    private fun item(v: String): Any {
        val t = v.trim()
        if (t.startsWith("<") && !t.startsWith("<html", true) && !t.startsWith("<!", true)) Jsoup.parseBodyFragment(t).body().children().singleOrNull()?.let { return it }
        return document(v)
    }

    internal fun firstLine(text: String) = text.lineSequence().map { it.trim() }.firstOrNull { it.isNotEmpty() }.orEmpty()

    fun search(source: NovelSource, key: String, page: Int = 1, category: NovelCategory? = null): List<NovelHit> {
        val raw = category?.url ?: source.json.optString("searchUrl")
        require(raw.isNotBlank()) { "书源没有搜索地址" }
        val response = page(raw, source, key, page)
        val rules = JSONObject(source.rules("ruleSearch").toString())
        if(category!=null)source.rules("ruleExplore").let { extra -> for(k in extra.keys())if(extra.optString(k).isNotBlank())rules.put(k,extra.get(k)) }
        require(listOf("bookList","name","bookUrl").all{rules.optString(it).isNotBlank()}){"书源缺少列表、书名或详情地址规则"}
        val base = response.url
        return nodes(document(response.text), rules.optString("bookList"),source,base,key,page).mapNotNull { node ->
            fun v(k:String)=ruleValue(node,rules.optString(k),source,base,key,page)
            // Optional fields (author, cover, latest…) must not drop the whole list when their rule fails, same as iOS.
            fun optional(k:String)=runCatching{v(k)}.getOrDefault("")
            // Legado reads URL rules with getString0: several matches give the first one, not a newline-joined list.
            val name = stripInvisible(v("name")).trim(); val url = firstLine(v("bookUrl"))
            if (name.isBlank() || url.isBlank()) null else NovelHit(name, optional("author"), absolute(url, base), runCatching{absolute(firstLine(optional("coverUrl")),base)}.getOrDefault(""),optional("kind"),optional("lastChapter"))
        }.distinctBy { it.url }
    }

    fun details(source: NovelSource, bookURL: String): NovelBookDetails = NovelScript.withBook(bookURL) {
        var detail:Any = document(page(bookURL, source).text)
        val info=source.rules("ruleBookInfo")
        if(info.optString("init").isNotBlank()) detail=nodes(detail,info.getString("init"),source,bookURL).firstOrNull() ?: detail
        // Book-info name rules often set variables required by TOC/content scripts.
        fun v(key: String) = runCatching { ruleValue(detail, info.optString(key), source, bookURL) }.getOrDefault("")
        val name = stripInvisible(v("name")); val author = v("author").replace(Regex("^作者[：:]\\s*"), "")
        val intro = v("intro"); val cover = firstLine(v("coverUrl")); val kind = v("kind"); val latest = v("lastChapter")
        val toc = ruleValue(detail, info.optString("tocUrl"),source,bookURL)
        var url = if (toc.isBlank()) bookURL else absolute(toc, bookURL)
        val rules = source.rules("ruleToc"); val out = arrayListOf<NovelChapter>(); val seen = hashSetOf<String>();val queue=ArrayDeque(listOf(url))
        while (seen.size < 100 && queue.isNotEmpty()) {
            url=queue.removeFirst();if(!seen.add(url))continue
            val doc = if (url == bookURL) detail else document(page(url, source).text)
            for (n in nodes(doc, rules.optString("chapterList"),source,url)) {
                val title = ruleValue(n, rules.optString("chapterName"),source,url); val address = ruleValue(n, rules.optString("chapterUrl"),source,url)
                if (title.isNotBlank() && address.isNotBlank()) out += NovelChapter(title, absolute(address, url))
            }
            val next = ruleValue(doc, rules.optString("nextTocUrl"),source,url)
            for(link in next.lines().filter{it.isNotBlank()}){val target=absolute(link,url);if(target !in seen && target !in queue)queue.add(target)}
        }
        NovelBookDetails(name, author, intro, if (cover.isBlank()) "" else runCatching{absolute(cover, bookURL)}.getOrDefault(""), kind, latest, out.distinctBy { it.url })
    }

    fun chapters(source: NovelSource, bookURL: String): List<NovelChapter> = details(source, bookURL).chapters

    fun content(source: NovelSource, chapter: NovelChapter, nextChapter: String? = null, bookURL: String? = null): String = NovelScript.withBook(bookURL) {
        val rules = source.rules("ruleContent"); var url = chapter.url; val seen = hashSetOf<String>(); val parts = arrayListOf<String>(); var imageOnly = false
        while (seen.size < 30 && seen.add(url)) {
            val doc = document(page(url, source).text)
            val raw = ruleValue(doc, rules.optString("content"),source,url)
            val cleaned = cleanText(raw)
            imageOnly = imageOnly || (cleaned.isBlank() && Regex("<img\\b",RegexOption.IGNORE_CASE).containsMatchIn(raw))
            parts += cleaned
            val next = ruleValue(doc, rules.optString("nextContentUrl"),source,url); if (next.isBlank()) break
            url = absolute(next, url); if (url == nextChapter) break
        }
        var text = parts.joinToString("\n\n")
        for (rule in rules.optString("replaceRegex").lines().filter { it.isNotBlank() }) {
            val p = rule.removePrefix("##").split("##"); text = text.replace(Regex(p[0]), p.getOrElse(1) { "" })
        }
        require(text.isNotBlank()) { if(imageOnly) "本章是图片页，请换文字版书源" else "章节正文为空或书源规则不兼容" }
        text
    }

    fun cleanText(raw: String): String = Jsoup.parse(raw.replace(Regex("(?i)<br\\s*/?>|</p>|</div>"), "\n")).wholeText()
        .lines().map { it.trim() }.filter { it.isNotEmpty() }.joinToString("\n")
}

/** Metadata and TOC from one real detail flow, shared by detail, shelf and download instead of a title-only TOC screen. */
data class NovelBookDetails(val name: String, val author: String, val intro: String, val cover: String, val kind: String, val latest: String, val chapters: List<NovelChapter>)
