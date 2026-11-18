package app.iduanju.core

import app.iduanju.core.novel.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Test

class NovelSourcesTest {
    @Test fun boundedStreamsGzipAndBigIntegers() {
        val s=NovelSource(org.json.JSONObject().put("bookSourceUrl","https://compat.test"))
        val code="""@js:var B=Packages.java.math.BigInteger;var out=new Packages.java.io.ByteArrayOutputStream();var gzip=new Packages.java.util.zip.GZIPOutputStream(out);gzip.write(new Packages.java.lang.String('中文 stream').getBytes());gzip.close();var reader=new Packages.java.io.BufferedReader(new Packages.java.io.InputStreamReader(new Packages.java.util.zip.GZIPInputStream({bytes:out.toByteArray()}),'UTF-8'));reader.readLine()+'|'+new B('12345678901234567890').modPow(new B('65537'),new B('999999999999999999989')).toString()+'|'+new B('128').toByteArray().join(',');"""
        assertEquals("中文 stream|578379236927338162488|0,-128",NovelSources.ruleValue("",code,s,s.id))
        assertThrows(Exception::class.java){NovelSources.ruleValue("","@js:new Packages.java.security.SecureRandom().generateSeed(99999999)",s,s.id)}
        assertThrows(Exception::class.java){NovelSources.ruleValue("","@js:new Packages.java.net.URL('file:///etc/passwd').openConnection().getResponseCode()",s,s.id)}
    }
    @After fun cleanup() { NovelSources.fixture = null; NovelSources.fixturePage = null }
    @Test fun htmlDiscoverySearchAndRead() {
        val source = NovelSources.import("""{"bookSourceUrl":"https://book.example","bookSourceName":"书站","searchUrl":"/search?q={{key}}&page={{page}}","exploreUrl":"热门::/rank?page={{page}}&&最新::/new","ruleSearch":{"bookList":"class.books@tag.li","name":"tag.a@text","bookUrl":"tag.a@href","author":"tag.span@text"},"ruleBookInfo":{"tocUrl":"id.toc@href"},"ruleToc":{"chapterList":"tag.li","chapterName":"tag.a@text","chapterUrl":"tag.a@href"},"ruleContent":{"content":"id.content@html"}}""").single()
        val categories = NovelSources.categories(source)
        assertEquals(listOf("热门", "最新"), categories.map { it.title })
        NovelSources.fixture = { u -> when {
            u.contains("/search") || u.contains("/rank") -> "<ul class='books'><li><a href='/book/1'>雾港</a><span>作者</span></li></ul>"
            u.endsWith("/book/1") -> "<a id='toc' href='/toc/1'>目录</a>"
            u.endsWith("/toc/1") -> "<ul><li><a href='/chapter/1'>第一章</a></li></ul>"
            u.endsWith("/chapter/1") -> "<div id='content'>第一段<br>第二段</div>"
            else -> error(u)
        } }
        val book = NovelSources.search(source, "雾港").single()
        assertEquals("雾港", book.name)
        assertEquals("https://book.example/book/1", book.url)
        assertEquals(book, NovelSources.search(source, "", category = categories.first()).single())
        val chapters = NovelSources.chapters(source, book.url)
        assertEquals("第一章", chapters.single().title)
        assertEquals("第一段\n第二段", NovelSources.content(source, chapters.single()))
    }
    @Test fun jsonDiscoveryAndExplicitUnsupportedRules() {
        val s = NovelSources.import("""[{"bookSourceUrl":"https://example.com","searchUrl":"/s","exploreUrl":[{"title":"榜单","url":"/rank"}],"ruleSearch":{"bookList":"$.list[*]","name":"$.name","bookUrl":"$.url"}}]""").single()
        assertEquals("榜单", NovelSources.categories(s).single().title)
        NovelSources.fixture = { """{"list":[{"name":"测试","url":"/book/1"}]}""" }
        assertEquals("测试", NovelSources.search(s, "").single().name)
        s.json.put("searchUrl", "@js:java.ajax('x')")
        assertThrows(Exception::class.java) { NovelSources.search(s, "") }
    }

    @Test fun scriptDiscoveryOptionsAndListRules() {
        val s=NovelSources.import("""{"bookSourceUrl":"https://example.com","bookSourceName":"脚本","exploreUrl":"@js:JSON.stringify([{title:'分类',url:''},{title:'玄幻',url:'{{address(page)}}'}])","jsLib":"function address(p){return 'https://example.com/r?page='+p+',{\"headers\":{\"X-Test\":\"ok\"}}';}","ruleExplore":{"bookList":"@js:JSON.parse(result).list.map(function(x){return JSON.stringify(x);})","name":"$.name","bookUrl":"$.url"}}""").single()
        val cats=NovelSources.categories(s)
        assertEquals(1,cats.size);assertEquals("分类",cats[0].group)
        NovelSources.fixture={ u -> assertEquals("https://example.com/r?page=2",u); """{"list":[{"name":"雾港","url":"/book/1"}]}""" }
        assertEquals("雾港",NovelSources.search(s,"",2,cats[0]).single().name)
        assertThrows(Exception::class.java) { NovelSources.ruleValue("", "@js:Packages.java.lang.Runtime.getRuntime().exec('anything')",s,s.id) }
    }

    @Test fun binaryChapterRequestsAndInflater() {
        val s=NovelSources.import("""{"bookSourceUrl":"https://binary.test"}""").single()
        val response=NovelSources.fetchResponse("data:;base64,aGVsbG8=,{\"type\":\"raw\"}",s)
        assertEquals("68656c6c6f",response.text)
        assertEquals("hello",NovelSources.ruleValue(response.text,"@js:java.hexDecodeToString(result)",s,response.url))
        val raw="chapter content".toByteArray()
        val deflater=java.util.zip.Deflater(6,true)
        val out=ByteArray(200)
        deflater.setInput(raw);deflater.finish();val n=deflater.deflate(out);deflater.end()
        val b64=java.util.Base64.getEncoder().encodeToString(out.copyOf(n))
        val script="""@js:var inf=new Packages.java.util.zip.Inflater(true);inf.setInput(java.base64DecodeToByteArray('$b64'));var out=new Array(50).fill(0);var n=inf.inflate(out);String(new Packages.java.lang.String(out,0,n,'UTF-8'))+'|'+inf.finished();"""
        assertEquals("chapter content|true",NovelSources.ruleValue("",script,s,s.id))
    }

    @Test fun bookStateIsolatedAndRestoredOnFailure() {
        val s=NovelSource(org.json.JSONObject().put("bookSourceUrl","https://scope.test"))
        NovelScript.withBook("bookA") { NovelSources.ruleValue("","@js:java.put('bid','A');source.put('shared','yes')",s,s.id) }
        NovelScript.withBook("bookB") { NovelSources.ruleValue("","@js:java.put('bid','B')",s,s.id) }
        assertEquals("A|yes",NovelScript.withBook("bookA") { NovelSources.ruleValue("","@js:java.get('bid')+'|'+source.get('shared')",s,s.id) })
        assertEquals("B",NovelScript.withBook("bookB") { NovelSources.ruleValue("","@js:java.get('bid')",s,s.id) })
        assertThrows(Exception::class.java) { NovelScript.withBook("bad") { error("fail") } }
        assertNull(NovelScript.bookURL.get())
    }

    @Test fun imageOnlyChapterIsNotCachedAsText() {
        val s=NovelSource(org.json.JSONObject("""{"bookSourceUrl":"https://image.test","ruleContent":{"content":"@js:'<p><img src=\"page.jpg\"></p>'"}}"""))
        NovelSources.fixture={"<html></html>"}
        val error=assertThrows(Exception::class.java){NovelSources.content(s,NovelChapter("chapter","https://image.test/1"))}
        assertTrue(error.message!!.contains("图片页"))
    }

    @Test fun realBundleContainsSourcesAndJsIsReportedClearly() {
        val path = System.getenv("NOVEL_COLLECTION")
        org.junit.Assume.assumeTrue("NOVEL_COLLECTION points at user-supplied 1335.json", path != null)
        val raw = java.io.File(path!!).readText()
        val sources = NovelSources.import(raw)
        assertTrue(sources.size >= 150)
        assertTrue(sources.count { it.json.optInt("bookSourceType", 0) == 0 } >= 140)
        val cat = sources.first { it.name == "猫扑中文" }
        assertTrue(NovelSources.categories(cat).any { it.title == "排行榜" })
        assertFalse(NovelSources.categories(cat).any { it.url.isBlank() && it.action == null })
    }
}


/** Offline pages actually captured from the user's 1335.json collection; source rules are unmodified. */
class RealRankRegressionTest {
    @After fun cleanup() { NovelSources.fixture = null; NovelSources.fixturePage = null }
    private fun bytes(name: String) = javaClass.getResourceAsStream("/legado-rank/$name")!!.use { it.readBytes() }
    @Test fun actualRankingToDetailAndTOCOffline() {
        val sources = org.json.JSONArray(String(bytes("sources.json")))
        for (n in 0 until sources.length()) {
            val json = sources.getJSONObject(n); val id = json.getInt("rankFixtureIndex"); val source = NovelSource(json)
            val routes = org.json.JSONArray(String(bytes("$id/routes.json")))
            val used = hashSetOf<Int>()
            fun stableURL(raw: String): String = java.net.URLDecoder.decode(raw, "UTF-8").let { u ->
                val path = u.substringBefore('?'); val query = u.substringAfter('?', "").split('&').filter { it.isNotBlank() && it.substringBefore('=') !in listOf("t", "sign") }.sorted().joinToString("&")
                path + if (query.isBlank()) "" else "?$query"
            }
            fun sameURL(a: String, b: String) = stableURL(a) == stableURL(b)
            NovelSources.fixturePage = { url ->
                val i = (0 until routes.length()).firstOrNull { it !in used && sameURL(routes.getJSONObject(it).getString("url"), url) }
                    ?: (0 until routes.length()).firstOrNull { sameURL(routes.getJSONObject(it).getString("url"), url) }
                    ?: error("unrecorded request $id $url")
                used += i
                val r = routes.getJSONObject(i)
                NovelSources.PageResponse(NovelSources.decode(bytes("$id/" + r.getString("file")), null, r.getString("contentType")), r.optString("responseURL", url))
            }
            val cats = NovelSources.categories(source)
            val c = cats.first { it.action == null && it.url.isNotBlank() }
            val hits = NovelSources.search(source, "", category = c)
            assertTrue("$id books", hits.size > 1)
            val book = hits.first(); assertFalse(book.url.contains("\n"))
            val details = NovelSources.details(source, book.url)
            val toc = details.chapters
            println("[metadata-offline] $id name=${details.name} author=${details.author} intro=${details.intro.length} cover=${details.cover}")
            assertTrue("$id toc", toc.size > 1)
            assertTrue(toc.first().title.isNotBlank())
            assertTrue(toc.first().url.startsWith("http"))
            println("[rank-offline] $id ${source.name}: cats=${cats.size} books=${hits.size} toc=${toc.size} first=${toc.first().title} url=${toc.first().url}")
        }
    }

    @Test fun liveRealCollectionRankingToTOC() {
        val file = System.getenv("STV_RANK_LIVE")
        org.junit.Assume.assumeTrue("set STV_RANK_LIVE to downloaded 1335.json", file != null)
        NovelSources.fixture = null
        val sources = org.json.JSONArray(java.io.File(file!!).readText())
        for (id in listOf(7, 28, 30, 65)) {
            val source = NovelSource(sources.getJSONObject(id))
            val cats = NovelSources.categories(source)
            val hits = NovelSources.search(source, "", category = cats.first { it.action == null && it.url.isNotBlank() })
            assertTrue(hits.isNotEmpty())
            val details = NovelSources.details(source, hits.first().url)
            val toc = details.chapters
            assertTrue(toc.size > 1)
            if(id==7){assertEquals(hits.first().name,details.name);assertTrue(details.intro.length>100);assertTrue(details.cover.startsWith("https://"))}
            println("[rank-live] $id ${source.name}: cats=${cats.size} books=${hits.size} toc=${toc.size}")
        }
    }
}
