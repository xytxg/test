package app.iduanju.core.novel

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Source + book + chapter URL keys survive TOC reordering without mixing books or sources. */
class NovelCache(private val root: File) {
    data class Saved(val source: String, val book: NovelHit, val chapters: List<NovelChapter>, val details: NovelBookDetails? = null, val addedAt: Long = 0)
    // Fixed stripes bound memory while sharing foreground/download/speculative fetches.
    private val chapterLocks = Array(64) { java.util.concurrent.locks.ReentrantLock() }
    fun load(source: String, book: String, url: String, checkActive: () -> Unit = {}, fetch: () -> String): String {
        val lock = chapterLocks[((source + "\n" + book + "\n" + url).hashCode() and Int.MAX_VALUE) % chapterLocks.size]
        checkActive()
        lock.lock()
        try {
            checkActive()
            return read(source, book, url) ?: fetch().also { checkActive(); save(source, book, url, it) }
        } finally { lock.unlock() }
    }
    private fun hash(value: String): String {
        val bytes=MessageDigest.getInstance("SHA-256").digest(value.toByteArray())
        val digits="0123456789abcdef"
        return String(CharArray(bytes.size*2){i->val b=bytes[i/2].toInt() and 255;digits[if(i%2==0)b ushr 4 else b and 15]})
    }
    private fun dir(source: String, book: String) = File(root, hash(source + "\n" + book))
    private fun chapter(source: String, book: String, url: String) = File(dir(source,book), hash(url) + ".txt")
    fun read(source: String, book: String, url: String): String? = chapter(source,book,url).takeIf { it.isFile && it.length() > 0 }?.readText()
    fun count(source: String, book: String, toc: List<NovelChapter>): Int {
        // One directory scan, not 1694 repeated book hashes and filesystem stats per page turn.
        val files=dir(source,book).listFiles().orEmpty().filter{it.isFile && it.name.endsWith(".txt") && it.length()>0}.map{it.name}.toHashSet()
        if(files.isEmpty())return 0
        return toc.count{hash(it.url)+".txt" in files}
    }
    private fun atomic(file: File, text: String) {
        file.parentFile!!.mkdirs()
        val tmp = File.createTempFile("chapter-", ".part", file.parentFile)
        try { tmp.writeText(text); Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING) } finally { tmp.delete() }
    }
    @Synchronized fun save(source: String, book: String, url: String, text: String) {
        require(text.isNotBlank()) { "正文为空，未写入缓存" }
        atomic(chapter(source,book,url),text)
    }
    @Synchronized fun saveBook(source: String, book: NovelHit, chapters: List<NovelChapter>, details: NovelBookDetails? = null) {
        val json = JSONObject().put("source",source).put("name",book.name).put("author",book.author).put("url",book.url).put("cover",book.cover)
            .put("chapters",JSONArray(chapters.map { JSONObject().put("title",it.title).put("url",it.url) }))
        val file=File(dir(source,book.url),"book.json")
        val previous=runCatching{JSONObject(file.readText())}.getOrNull()
        json.put("addedAt",previous?.optLong("addedAt",0) ?: System.currentTimeMillis())
        val info=details?.let{JSONObject().put("name",it.name).put("author",it.author).put("intro",it.intro).put("cover",it.cover).put("kind",it.kind).put("latest",it.latest)}
            ?: runCatching{JSONObject(file.readText()).optJSONObject("info")}.getOrNull()
        if(info!=null)json.put("info",info)
        atomic(file,json.toString())
    }
    data class SearchHit(val chapter:Int,val offset:Int,val snippet:String)
    /** Search real cached text only; opening a TOC must never download the entire book. */
    fun search(source:String,book:String,toc:List<NovelChapter>,query:String,limit:Int=200):List<SearchHit> {
        val q=query.trim();if(q.isEmpty())return emptyList()
        val out=ArrayList<SearchHit>()
        for((i,ch) in toc.withIndex()) {
            val text=read(source,book,ch.url)?.lineSequence()?.map{it.trim()}?.filter{it.isNotBlank()}?.joinToString("\n")?:continue
            var at=0
            while(out.size<limit){val found=text.indexOf(q,at,ignoreCase=true);if(found<0)break
                val start=(found-16).coerceAtLeast(0);out+=SearchHit(i,found,text.substring(start,minOf(text.length,start+60)).replace('\n',' '));at=found+q.length
            }
            if(out.size>=limit)break
        }
        return out
    }
    fun books(): List<Saved> = root.listFiles().orEmpty().filter { it.isDirectory }.mapNotNull { directory ->
        runCatching { val j=JSONObject(File(directory,"book.json").readText());val a=j.getJSONArray("chapters")
            val toc=(0 until a.length()).map { a.getJSONObject(it).let { c -> NovelChapter(c.getString("title"),c.getString("url")) } }
            val info=j.optJSONObject("info")?.let{NovelBookDetails(it.optString("name"),it.optString("author"),it.optString("intro"),it.optString("cover"),it.optString("kind"),it.optString("latest"),toc)}
            Saved(j.getString("source"),NovelHit(j.getString("name"),j.optString("author"),j.getString("url"),j.optString("cover")),toc,info,j.optLong("addedAt",0))
        }.getOrNull()
    }
}
