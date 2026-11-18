package app.iduanju.core.hongguo

import app.iduanju.core.util.J
import app.iduanju.core.util.GoURL
import app.iduanju.core.util.ProviderException
import org.json.JSONObject

data class HGRankedActor(val id: String, val name: String, val avatar: String, val rank: Int,
    val score: String, val intro: String, val works: List<String>, val change: Int, val changeNum: Int)
data class HGActorRankPage(val actors: List<HGRankedActor>, val date: String, val hasMore: Boolean, val nextOffset: Int, val sessionId: String)

object HGActorRank {
    fun fetch(client: HongguoClient, offset: Int = 0, sessionId: String = "", startRank: Int = 0): HGActorRankPage {
        val d = client.ensureDevice()
        val query = "background_selected_items=&category_id=0&cell_id=7470092475068071998&cell_sub_id=0" +
            "&client_req_type=2&client_template=2&filter_ids=&gender=2&limit=20&offset=$offset&panel_selected_items=" +
            "&selected_items=ranklist_celebrity&session_id=${GoURL.queryEscape(if (offset == 0) "" else sessionId)}" +
            "&sub_selected_items=ranklist_series_actor&tab_type=${if (offset == 0) 26 else 18}&unlimited_selector_change_type=0&" +
            client.listQuery(d, System.currentTimeMillis())
        val response = client.list(HongguoClient.URL_RANK_CELL + query)
        if (J.str(response.opt("code")) != "0") throw ProviderException.upstream("剧星榜请求失败")
        return parse(J.dict(response.opt("data")), offset, sessionId, startRank)
    }

    fun parse(data: JSONObject, offset: Int = 0, sessionId: String = "", startRank: Int = 0): HGActorRankPage {
        val cv = J.dict(data.opt("cell_view"))
        val outer = J.arr(J.dict(J.dict(cv.opt("cell_selector")).opt("outer_row")).opt("items"))
            .map { J.dict(it) }.firstOrNull { J.bool(it.opt("is_selected")) }
        if (outer != null) {
            val id = J.str(outer.opt("selector_item_id"))
            if (id.isNotEmpty() && id != "ranklist_celebrity") throw ProviderException.upstream("服务端未选中演员榜")
            val sub = J.arr(J.dict(J.dict(outer.opt("sub_cell_selector")).opt("outer_row")).opt("items"))
                .map { J.dict(it) }.firstOrNull { J.bool(it.opt("is_selected")) }
            val subId = J.str(sub?.opt("selector_item_id"))
            if (subId.isNotEmpty() && subId != "ranklist_series_actor") throw ProviderException.upstream("服务端未选中剧星榜")
        }
        fun clean(s: String) = org.jsoup.Jsoup.parse(s).text()
        val actors = arrayListOf<HGRankedActor>()
        for (cell in J.arr(cv.opt("cell_data"))) for (raw in J.arr(J.dict(cell).opt("ugc_user_data"))) {
            val m = J.dict(raw); val base = J.dict(J.dict(m.opt("user_info")).opt("base_info"))
            val id = J.str(base.opt("actor_id_str")); val name = clean(J.str(base.opt("user_name")))
            if (id.isEmpty() || name.isEmpty()) continue
            val change = J.dict(m.opt("rank_change_data"))
            actors += HGRankedActor(id, name, J.str(base.opt("user_avatar")), startRank + actors.size + 1,
                J.str(J.dict(m.opt("rec_text_item")).opt("RecommendText")), clean(J.str(m.opt("intro"))),
                J.arr(m.opt("sub_title_list")).map { clean(J.str(J.dict(it).opt("content"))) }.filter { it.isNotEmpty() },
                J.int(change.opt("rank_change_type")), J.int(change.opt("ChangeNum")))
        }
        val date = runCatching { JSONObject(cv.optString("cell_data_json")).optString("rank_list_date") }.getOrDefault("")
        return HGActorRankPage(actors, date, J.bool(data.opt("has_more")),
            J.int(data.opt("next_offset")).takeIf { it > offset } ?: (offset + actors.size), J.str(data.opt("session_id")).ifEmpty { sessionId })
    }
}
