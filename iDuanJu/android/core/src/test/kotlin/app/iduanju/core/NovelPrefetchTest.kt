package app.iduanju.core

import app.iduanju.core.novel.*
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.*
import java.util.concurrent.atomic.AtomicInteger

class NovelPrefetchTest {
    @Test fun boundedNeighborFirstPlan() {
        assertEquals(listOf(6,4,7,8,3,2),NovelPrefetchPlan.indices(5,12,3))
        assertEquals(listOf(1,2,3),NovelPrefetchPlan.indices(0,4,20))
        assertEquals(listOf(2,1,0),NovelPrefetchPlan.indices(3,4,20))
        assertTrue(NovelPrefetchPlan.indices(0,10,0).isEmpty())
        assertTrue(NovelPrefetchPlan.indices(-1,10,3).isEmpty())
    }
    @Test fun foregroundAndPrefetchShareInFlightFetchAndCache() {
        val root=kotlin.io.path.createTempDirectory("novel-dedup").toFile()
        val executor=Executors.newFixedThreadPool(2)
        try {
            val cache=NovelCache(root);val started=CountDownLatch(1);val release=CountDownLatch(1);val calls=AtomicInteger()
            val a=executor.submit<String>{cache.load("source","book","chapter"){calls.incrementAndGet();started.countDown();check(release.await(3,TimeUnit.SECONDS));"real cached body"}}
            assertTrue(started.await(3,TimeUnit.SECONDS))
            val b=executor.submit<String>{cache.load("source","book","chapter"){calls.incrementAndGet();"must not fetch"}}
            release.countDown();assertEquals("real cached body",a.get(3,TimeUnit.SECONDS));assertEquals(a.get(),b.get(3,TimeUnit.SECONDS));assertEquals(1,calls.get())
        } finally {executor.shutdownNow();root.deleteRecursively()}
    }
    @Test fun historicalCacheKeysAndTOCIntersectionArePreserved() {
        val root=kotlin.io.path.createTempDirectory("novel-legacy-cache").toFile()
        try {
            fun oldHash(value:String)=java.security.MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString(""){"%02x".format(it)}
            val folder=java.io.File(root,oldHash("source\nbook")).apply{mkdirs()}
            java.io.File(folder,oldHash("chapter")+".txt").writeText("previous-version chapter")
            java.io.File(folder,oldHash("orphan")+".txt").writeText("not in this TOC")
            java.io.File(folder,oldHash("empty")+".txt").writeText("")
            val cache=NovelCache(root)
            assertEquals("previous-version chapter",cache.read("source","book","chapter"))
            assertEquals(1,cache.count("source","book",listOf(NovelChapter("one","chapter"),NovelChapter("two","missing"),NovelChapter("empty","empty"))))
            cache.save("source","book","new","new body")
            assertEquals("new body",java.io.File(folder,oldHash("new")+".txt").readText())
        } finally {root.deleteRecursively()}
    }
    @Test fun metadataSurvivesOfflineReloadAndLegacySaveCalls() {
        val root=kotlin.io.path.createTempDirectory("novel-metadata").toFile()
        try {
            val cache=NovelCache(root);val book=NovelHit("title","author","https://book");val toc=listOf(NovelChapter("one","https://chapter"))
            val info=NovelBookDetails("title","author","intro\nsecond paragraph","https://cover","kind","latest",toc)
            cache.saveBook("source",book,toc,info)
            cache.saveBook("source",book,toc) // download/old callers must not erase detail metadata
            assertEquals(info,NovelCache(root).books().single().details)
        } finally {root.deleteRecursively()}
    }
    @Test fun cancelledBlockingResponseCannotPoisonCacheAndCanRetry() {
        val root=kotlin.io.path.createTempDirectory("novel-cancel").toFile()
        try {
            val cache=NovelCache(root);var cancelled=false
            assertThrows(CancellationException::class.java){cache.load("s","b","c",{if(cancelled)throw CancellationException()}){cancelled=true;"obsolete response"}}
            assertNull(cache.read("s","b","c"))
            assertEquals("fresh response",cache.load("s","b","c"){"fresh response"})
            assertEquals("other book",cache.load("s","other","c"){"other book"})
            assertEquals("other source",cache.load("other","b","c"){"other source"})
        } finally {root.deleteRecursively()}
    }
}
