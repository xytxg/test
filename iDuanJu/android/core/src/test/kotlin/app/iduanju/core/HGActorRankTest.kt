package app.iduanju.core

import app.iduanju.core.hongguo.HGActorRank
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class HGActorRankTest {
    @Test fun parsesRankingAndRejectsSubstitutedBoard() {
        val data = JSONObject("""{"has_more":true,"next_offset":20,"session_id":"next","cell_view":{"cell_data":[{"ugc_user_data":[{"user_info":{"base_info":{"actor_id_str":"a1","user_name":"<b>演员</b>","user_avatar":"https://example.com/a.jpg"}},"rec_text_item":{"RecommendText":"热度 123"},"sub_title_list":[{"content":"代表作"}],"rank_change_data":{"rank_change_type":1,"ChangeNum":3}}]}]}}""")
        val page = HGActorRank.parse(data, startRank = 20)
        assertEquals(21, page.actors.single().rank)
        assertEquals("演员", page.actors.single().name)
        assertEquals("热度 123", page.actors.single().score)
        assertEquals("next", page.sessionId)
        assertTrue(page.hasMore)
        data.getJSONObject("cell_view").put("cell_selector", JSONObject("""{"outer_row":{"items":[{"is_selected":true,"selector_item_id":"wrong"}]}}"""))
        assertThrows(Exception::class.java) { HGActorRank.parse(data) }
    }
}
