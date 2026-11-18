package app.iduanju.core

import app.iduanju.core.hongguo.*
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HGCategoryTest {
    @Test fun liveGenrePanelsAndPagination() {
        org.junit.Assume.assumeTrue(System.getProperty("idj.live") == "1")
        val client = HongguoClient(java.io.File("build/hg-genre-live"))
        for (genre in listOf("short_play", "comic_series", "ai_series")) {
            val panel = client.panel(genre)
            assertTrue("$genre panel empty", panel.rows.isNotEmpty())
            val ids = mutableListOf(genre)
            if (genre == "comic_series") {
                val urban = panel.rows.firstOrNull { it.type == "category_dim_epoch" }?.items?.firstOrNull { it.name == "都市" }
                assertNotNull("comic urban filter missing", urban)
                ids += urban!!.id
            }
            val first = client.category(ids)
            println("[genre] $genre rows=${panel.rows.size} first=${first.items.size} hasMore=${first.hasMore}")
            assertTrue("$genre content empty", first.items.isNotEmpty())
            if (first.hasMore) {
                val second = client.category(ids, first.nextOffset!!, first.sessionId, first.items.map { it.seriesId })
                println("[genre] $genre second=${second.items.size}")
                assertTrue("$genre continuation empty", second.items.isNotEmpty())
                assertTrue("$genre repeated first page", second.items.none { s -> first.items.any { it.seriesId == s.seriesId } })
            }
        }
    }
    @Test fun genreScopedIDsAndRequestScene() {
        val client=HongguoClient(java.nio.file.Files.createTempDirectory("category-contract").toFile())
        val comic=HGPanel(listOf(HGFilterRow("genre","剧种",2,listOf(HGFilterOption("comic_series","漫剧"))),
            HGFilterRow("category_dim_epoch","背景",2,listOf(HGFilterOption("cate_1","都市")))))
        assertEquals(listOf("cate_1"),client.categorySelection(comic,listOf("comic_series","cate_1"))["category_dim_epoch"])
        assertThrows(Exception::class.java){client.categorySelection(comic,listOf("comic_series","cate_5022"))}
        for(genre in listOf("short_play","comic_series","ai_series")) {
            val b=JSONObject(String(client.categoryBody(mapOf("genre" to listOf(genre)),12,"next",listOf("1","2"),true)))
            assertEquals(if(genre=="short_play")"default" else genre,b.getString("req_scene"))
            assertEquals("1,2",b.getString("filter_ids"));assertEquals("only_panel",b.getString("req_type"))
        }
    }
}
