package app.iduanju.core

import app.iduanju.core.hongguo.HGRankGenre
import app.iduanju.core.hongguo.HGRankSub
import app.iduanju.core.hongguo.HongguoClient
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.nio.file.Files

/**
 * Live (`-Plive=1`): consecutive episodes through the app's real resolve path. With video_model signed by
 * the current Medusa envelope (HGCurrentPlayer, same as iOS), a healthy registered identity is reused.
 */
class HGPureRepeatLiveTest {
    @Test fun consecutiveEpisodesResolve() {
 assumeTrue(System.getProperty("idj.live") == "1")
 val hg = HongguoClient(Files.createTempDirectory("hg").toFile())
        val sid = hg.rank(HGRankSub.hot, HGRankGenre.all).items.first().seriesId
        val eps = hg.detail(sid).episodes.take(6)
        val seq = eps.joinToString("") { e ->
     val r = hg.resolveFresh(e.vid)
     Thread.sleep(1500)
     if (r.streams.isNotEmpty()) "P" else "F"
 }
        println("[live] resolveFresh ${eps.size} episodes: $seq route=${hg.lastPureRoute}")
 assertEquals("P".repeat(eps.size), seq)
    }
}
