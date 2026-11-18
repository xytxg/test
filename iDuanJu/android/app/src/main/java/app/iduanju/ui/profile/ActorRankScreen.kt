package app.iduanju.ui.profile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.iduanju.IdjApp
import app.iduanju.core.hongguo.HGActorRank
import app.iduanju.core.hongguo.HGRankedActor
import app.iduanju.ui.theme.IdjThemeColors
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun ActorRankScreen(onBack: () -> Unit, onSearch: (String) -> Unit) {
    val actors = remember { mutableStateListOf<HGRankedActor>() }
    var offset by remember { mutableIntStateOf(0) }
    var session by remember { mutableStateOf("") }
    var date by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var more by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    suspend fun load() {
        if (busy || !more) return
        busy = true; error = null
        try {
            val count = actors.size
            val p = withContext(Dispatchers.IO) { HGActorRank.fetch(IdjApp.instance.hongguo, offset, session, count) }
            val seen = actors.map { it.id }.toHashSet()
            val fresh = p.actors.filter { seen.add(it.id) }
            actors.addAll(fresh); offset = p.nextOffset; session = p.sessionId; date = p.date
            more = p.hasMore && fresh.isNotEmpty()
        } catch (e: CancellationException) { throw e }
        catch (e: Exception) { error = e.message }
        finally { busy = false }
    }
    LaunchedEffect(Unit) { load() }
    Column(Modifier.fillMaxSize().statusBarsPadding().padding(horizontal = 16.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = onBack) { Text("返回") }
            Text("剧星榜", color = IdjThemeColors.text, modifier = Modifier.padding(12.dp))
            TextButton(onClick = { if (!busy) { actors.clear(); offset = 0; session = ""; more = true; scope.launch { load() } } }) { Text("刷新") }
        }
        if (date.isNotEmpty()) Text(date, color = IdjThemeColors.secondary)
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 32.dp)) {
            items(actors, key = { it.id }) { a ->
                Row(Modifier.fillMaxWidth().clickable { onSearch(a.name) }.padding(vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("${a.rank}", color = IdjThemeColors.accent)
                    coil.compose.AsyncImage(a.avatar, null, Modifier.size(48.dp))
                    Column(Modifier.weight(1f)) {
                        Text(a.name, color = IdjThemeColors.text)
                        Text(a.score, color = IdjThemeColors.accent)
                        if (a.works.isNotEmpty()) Text(a.works.joinToString(" · "), color = IdjThemeColors.secondary, maxLines = 2)
                        if (a.intro.isNotEmpty()) Text(a.intro, color = IdjThemeColors.secondary, maxLines = 2)
                    }
                }
            }
            item {
                if (busy) CircularProgressIndicator()
                else if (more) TextButton(onClick = { scope.launch { load() } }) { Text(error?.let { "$it · 重试" } ?: "加载更多") }
                else if (actors.isEmpty()) Text("暂无榜单数据", color = IdjThemeColors.secondary)
            }
        }
    }
}
