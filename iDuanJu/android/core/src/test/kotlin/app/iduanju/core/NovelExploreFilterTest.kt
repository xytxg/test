package app.iduanju.core

import app.iduanju.core.novel.*
import org.json.JSONObject
import org.junit.*
import org.junit.Assert.*
import java.io.File

class NovelExploreFilterTest {
    @After fun cleanup(){NovelSources.fixture=null;NovelSources.fixturePage=null}
    @Test fun typedControlsPersistSourceStateAndRegenerateSelectedUrl(){
        val s=NovelSource(JSONObject().put("bookSourceUrl","https://filters.test/"+java.util.UUID.randomUUID()).put("exploreUrl","""@js:JSON.stringify([
            {title:'分组',url:''},
            {title:'关键词',type:'text',default:'a',action:"source.put('applied',infoMap.get('关键词'))"},
            {title:'完成',type:'toggle',chars:['off','on'],default:'off'},
            {title:'排序',type:'select',chars:['hot','new'],default:'new',viewName:"'排序 '+infoMap.get('排序')",style:{layout_flexBasisPercent:1,layout_wrapBefore:true}},
            {title:'榜单',url:'/rank?sort='+(infoMap.get('排序')||'new')+'&q='+(infoMap.get('关键词')||'a')+'&page={{page}}'}
        ])"""))
        val initial=NovelSources.categories(s)
        assertEquals(listOf("text","toggle","select","url"),initial.map{it.type})
        assertTrue(initial.all{it.group=="分组"});assertEquals("new",initial[2].value);assertEquals("排序 new",initial[2].displayTitle)
        assertEquals(1.0,initial[2].style.basis,0.0);assertTrue(initial[2].style.wrapBefore)
        NovelSources.categoryAction(s,initial[0],"b");NovelSources.categoryAction(s,initial[1]);NovelSources.categoryAction(s,initial[2],"hot")
        val refreshed=NovelScript.withBook("unrelated-book"){NovelSources.categories(s)}
        assertEquals("b",refreshed[0].value);assertEquals("on",refreshed[1].value);assertEquals("hot",refreshed[2].value)
        assertEquals("b",NovelSources.ruleValue("","@js:source.get('applied')",s,s.id))
        assertEquals("true",NovelSources.ruleValue("","@js:String(infoMap.get('missing')===null)",s,s.id))
        val chosen=NovelSources.refreshedCategory(initial.last(),refreshed,"分组")!!
        assertEquals("榜单",chosen.title);assertNotEquals(initial.last().url,chosen.url);assertTrue(chosen.url.contains("sort=hot&q=b"))
        NovelSources.ruleValue("","@js:infoMap.put('关键词','c');infoMap['完成']='off';'ok'",s,s.id)
        assertEquals("c",NovelSources.categories(s)[0].value);assertEquals("off",NovelSources.categories(s)[1].value)
    }

    @Test fun staleBackgroundScriptCannotOverwriteNewerFilterSelection(){
        val s=NovelSource(JSONObject().put("bookSourceUrl","https://filter-race.test/"+java.util.UUID.randomUUID()))
        val control=NovelCategory("sort","",type="select",chars=listOf("new","hot"))
        NovelSources.categoryAction(s,control,"new")
        NovelSources.fixture={NovelSources.categoryAction(s,control,"hot");"ok"}
        NovelSources.ruleValue("","@js:java.ajax('/gate');infoMap.put('other','kept');'ok'",s,s.id)
        val info=NovelScript.exploreInfo(s.id)
        assertEquals("hot",info.getString("sort"));assertEquals("kept",info.getString("other"))
    }
    @Test fun cosmeticViewNameFailureKeepsUsableCategories(){
        val s=NovelSource(JSONObject().put("bookSourceUrl","https://view-name.test").put("exploreUrl","""[{"title":"筛选","type":"button","viewName":"missingFunction()"},{"title":"榜单","url":"/rank"}]"""))
        val cats=NovelSources.categories(s);assertEquals(2,cats.size);assertEquals("筛选",cats.first().displayTitle)
    }

    /** Explicit, optional public-network capture; ordinary offline tests never fetch replacement pages. */
    @Test fun recordExactSourcePublicIndexes(){
        val out=System.getenv("STV_CAPTURE_QIMAO")
        Assume.assumeTrue("explicit capture only",out!=null)
        val source=NovelSource(JSONObject(javaClass.getResourceAsStream("/legado-rank/source7-exact.json")!!.bufferedReader().readText()))
        val dir=File(out!!).apply{mkdirs()}
        for((name,js) in listOf("source7-category-index.json" to "qmIndex(1)","source7-rank-index.json" to "qmRankIndex(1)")){
            val raw=File(dir,name).takeIf{it.exists()}?.readText() ?: NovelSources.ruleValue("","@js:java.ajax($js)",source,source.id)
            assertTrue("real API returned data",JSONObject(raw).has("data"));File(dir,name).writeText(raw)
        }
        val old=NovelScript.storage;NovelScript.storage=java.util.concurrent.ConcurrentHashMap()
        try {
            NovelSources.fixture={u->File(dir,if(u.contains("/api/v5/category/index"))"source7-category-index.json" else if(u.contains("/api/v1/leader-board"))"source7-rank-index.json" else error(u)).readText()}
            var cats=NovelSources.categories(source)
            NovelSources.categoryAction(source,cats.first{it.title.startsWith("⚙ 筛选")});cats=NovelSources.categories(source)
            var chosen=cats.first{!it.isControl}
            val routes=org.json.JSONArray()
            for((i,title) in listOf<String?>(null,"完结","50-100万","按评分").withIndex()) {
                if(title!=null){NovelSources.categoryAction(source,cats.first{it.title==title});cats=NovelSources.categories(source);chosen=NovelSources.refreshedCategory(chosen,cats,chosen.group)!!}
                NovelSources.fixture=null
                val raw=NovelSources.fetch(chosen.url,source)
                assertTrue(JSONObject(raw).has("data"))
                val name="source7-filter-$i.json";File(dir,name).writeText(raw)
                val request=NovelSources.ruleValue("","@js:"+chosen.url.removePrefix("{{").removeSuffix("}}"),source,source.id)
                routes.put(JSONObject().put("file",name).put("url",request.substringBefore(",{",request)))
            }
            File(dir,"source7-filter-routes.json").writeText(routes.toString(2))
        } finally { NovelScript.storage=old;NovelSources.fixture=null }
    }

    @Test fun exactUserQimaoFilterActionsKeepCategoryAndChangeUrlSnapshot(){
        fun asset(name:String)=javaClass.getResourceAsStream("/legado-rank/$name")!!.bufferedReader().use{it.readText()}
        val source=NovelSource(JSONObject(asset("source7-exact.json")))
        val old=NovelScript.storage;NovelScript.storage=java.util.concurrent.ConcurrentHashMap()
        try{
            NovelSources.fixture={u->when{u.contains("/api/v5/category/index?")->asset("source7-category-index.json");u.contains("/api/v1/leader-board?")->asset("source7-rank-index.json");else->error("unrecorded real-source request: $u")}}
            var cats=NovelSources.categories(source)
            val original=cats.first{it.title=="爽文"&&!it.isControl}
            NovelSources.categoryAction(source,cats.first{it.title.startsWith("⚙ 筛选")})
            cats=NovelSources.categories(source)
            NovelSources.categoryAction(source,cats.first{it.title=="完结"})
            cats=NovelSources.categories(source)
            NovelSources.categoryAction(source,cats.first{it.title=="50-100万"})
            cats=NovelSources.categories(source)
            NovelSources.categoryAction(source,cats.first{it.title=="按评分"})
            cats=NovelSources.categories(source)
            val chosen=NovelSources.refreshedCategory(original,cats,original.group)!!
            assertEquals(original.selectionKey,chosen.selectionKey);assertNotEquals(original.url,chosen.url)
            assertTrue(chosen.url.endsWith(",page,1,2,2)}}"))
            assertTrue(cats.first{it.title.startsWith("⚙ 筛选")}.style.basis==1.0)
            var requested=""
            NovelSources.fixture={u->requested=u;error("URL-only assertion; no replacement response")}
            assertThrows(Exception::class.java){NovelSources.fetchResponse(chosen.url,source,page=2)}
            assertTrue(requested.contains("page=2"));assertTrue(requested.contains("over=1"));assertTrue(requested.contains("words=2"));assertTrue(requested.contains("sort=2"))
        }finally{NovelScript.storage=old}
    }
}
