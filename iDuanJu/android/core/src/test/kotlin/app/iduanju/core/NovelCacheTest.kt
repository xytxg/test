package app.iduanju.core

import app.iduanju.core.novel.*
import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files

class NovelCacheTest {
    @Test fun cachedBookSearchAndImportDateSurviveMetadataRefresh(){
        val cache=NovelCache(java.nio.file.Files.createTempDirectory("novel-search").toFile())
        val book=NovelHit("real-fixture-unit","","https://book.test/1");val toc=listOf(NovelChapter("一","https://book.test/c1"),NovelChapter("二","https://book.test/c2"))
        cache.saveBook("s",book,toc);val added=cache.books().single().addedAt;assertTrue(added>0)
        cache.save("s",book.url,toc[0].url,"  段落内容\n第二段命中")
        cache.saveBook("s",book,toc)
        assertEquals(added,cache.books().single().addedAt)
        val hit=cache.search("s",book.url,toc,"命中").single();assertEquals(0,hit.chapter);assertTrue(hit.offset>0)
        assertTrue(cache.search("s",book.url,toc,"不存在").isEmpty())
    }
    @Test fun offlineReloadAndSourceIsolation() {
        val dir=Files.createTempDirectory("novel-cache").toFile()
        try {
            val cache=NovelCache(dir);val book=NovelHit("雾港","作者","https://book.test/b")
            val toc=listOf(NovelChapter("一","https://book.test/1"),NovelChapter("二","https://book.test/2"))
            cache.saveBook("sourceA",book,toc);cache.save("sourceA",book.url,toc[1].url,"第二章正文")
            val fresh=NovelCache(dir)
            assertEquals(1,fresh.count("sourceA",book.url,toc))
            assertEquals("第二章正文",fresh.read("sourceA",book.url,toc.reversed()[0].url))
            assertNull(fresh.read("sourceB",book.url,toc[1].url))
            assertEquals(toc,fresh.books().single().chapters)
            assertThrows(Exception::class.java) { cache.save("sourceA",book.url,toc[0].url,"") }
        } finally { dir.deleteRecursively() }
    }
}
