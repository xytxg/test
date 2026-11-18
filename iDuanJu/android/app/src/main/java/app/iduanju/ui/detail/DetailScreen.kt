package app.iduanju.ui.detail

import androidx.compose.foundation.background
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Star
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import app.iduanju.ui.components.*
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.iduanju.IdjApp
import app.iduanju.core.hongguo.HGEpisode
import app.iduanju.core.hongguo.HGSeries
import app.iduanju.core.hongguo.HGSeriesDetail
import app.iduanju.ui.home.HomeFmt
import app.iduanju.ui.theme.IdjThemeColors
import coil.compose.AsyncImage
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Same as iOS/spec: groups of 30 (≤300), 50 (≤600), 60; ≤30 one group. */
object EpisodeGroups {
    fun size(total: Int) = when { total <= 30 -> maxOf(total, 1); total <= 300 -> 30; total <= 600 -> 50; else -> 60 }
    fun ranges(total: Int): List<IntRange> {
        if (total <= 0) return emptyList()
        val g = size(total)
        if (total <= g) return listOf(0 until total)
        return (0 until total step g).map { it..minOf(it + g - 1, total - 1) }
    }
    fun label(r: IntRange, eps: List<HGEpisode>): String {
        val a = eps.getOrNull(r.first)?.ep ?: (r.first + 1); val b = eps.getOrNull(r.last)?.ep ?: (r.last + 1)
        return if (a == b) "$a" else "$a-$b"
    }
}

/** ui-redesign 12 / 13: blurred poster hero + poster card, stats card, actions, tags, folding intro, 选集 → 系列 → 演员;
 *  a pinned nav once the hero scrolls away and a floating play bar once the main button leaves the screen. */
@Composable
fun DetailScreen(seriesId: String, onBack: () -> Unit, onPlay: (String, Int) -> Unit, onOpenSeries: (String) -> Unit = {}) {
    val c = IdjThemeColors
    val lib = IdjApp.instance.library
    var d by remember { mutableStateOf<HGSeriesDetail?>(null) }
    var err by remember { mutableStateOf<String?>(null) }
    var reload by remember { mutableIntStateOf(0) }
    LaunchedEffect(seriesId, reload) {
        err = null
        try { d = if(app.iduanju.BuildConfig.DEBUG && seriesId in listOf("ui-color-bars", "ui-detail-sparse", "ui-detail-full")) HGSeriesDetail(
            seriesId=seriesId,title="本地界面测试 · 非真实片源",desc="此页面使用明确标注的本地样例数据，用于检查详情页的排版、折叠、选集和滚动吸顶，不代表真实片源服务。".repeat(4),
            author="界面验证",totalEps=48,episodes=(1..48).map{app.iduanju.core.hongguo.HGEpisode(it,"fixture-$it",60,"测试第 $it 集")},
            tags=listOf("本地样例","排版验证"),favoriteCount=403000,
            rating=if(seriesId=="ui-detail-sparse")0.0 else 8.6,ratingCount=if(seriesId=="ui-detail-sparse")"" else "1.2万",
            hotText=if(seriesId=="ui-detail-sparse")"" else "512万",source="本地样例",
            relatedSeries=(1..3).map { HGSeries(seriesId=if(it==1)seriesId else "sample-$it",title="本地系列样例 $it",episodeCount=48) },
            cast=(1..5).map { app.iduanju.core.hongguo.HGCelebrity(id="sample-$it",name="样例演员 $it",role="饰 样例") })
            else withContext(Dispatchers.IO) { app.iduanju.data.Catalog.detail(seriesId) } }
        catch (e: Exception) { err = e.message ?: "加载失败" }
    }
    val resume = lib.progress(seriesId)
    var group by remember(d) {
        mutableIntStateOf(d?.let { dd -> EpisodeGroups.ranges(dd.episodes.size).indexOfFirst { resume != null && resume.episodeIndex in it }.coerceAtLeast(0) } ?: 0)
    }
    val scroll = rememberScrollState()
    LaunchedEffect(d) { if(d!=null && app.iduanju.BuildConfig.DEBUG && app.iduanju.ui.UiEvidence.scroll) { kotlinx.coroutines.delay(1200); scroll.scrollTo((scroll.maxValue*0.75).toInt()) } }
    val density = LocalDensity.current
    val pinned by remember { derivedStateOf { scroll.value > with(density) { 236.dp.toPx() } } }
    var actionsBottom by remember { mutableFloatStateOf(Float.MAX_VALUE) }
    val actionsOut = actionsBottom < with(density) { 100.dp.toPx() }
    val startEp = resume?.episodeNumber ?: d?.episodes?.firstOrNull()?.ep ?: 1
    val playTitle = if (resume != null) "继续第 ${resume.episodeNumber} 集" else "开始播放"

    Box(Modifier.fillMaxSize().background(c.bg)) {
        Column(Modifier.fillMaxSize().verticalScroll(scroll).navigationBarsPadding().padding(bottom = 110.dp)) {
            DetailHero(d, seriesId)
            val dd = d
            when {
                dd != null -> DetailBody(dd, seriesId, resume, group, { group = it }, onPlay, onOpenSeries, playTitle, startEp) { actionsBottom = it }
                err != null -> Column(Modifier.fillMaxWidth().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(err!!, color = c.secondary, fontSize = 14.sp, textAlign = TextAlign.Center)
                    Spacer(Modifier.height(12.dp))
                    MiniButton("重试") { reload++ }
                }
                else -> Column(Modifier.padding(horizontal = 20.dp).padding(top = 18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(Modifier.fillMaxWidth().height(66.dp).clip(RoundedCornerShape(16.dp)).background(c.glass))
                    repeat(3) { Box(Modifier.fillMaxWidth().height(16.dp).clip(RoundedCornerShape(4.dp)).background(c.glass)) }
                }
            }
        }
        // pinned nav (`.pin` + `.nav`)
        Box(Modifier.fillMaxWidth().dsPinned(pinned)) {
            DSNavBar(d?.title ?: "", Modifier.statusBarsPadding().padding(bottom = 6.dp), titleAlpha = animateFloatAsState(if (pinned) 1f else 0f, label = "t").value,
                leading = { BackButton(if (pinned) Tone.Glass else Tone.Overlay, onBack) })
        }
        // floating play bar (`.playbar`)
        AnimatedVisibility(d?.episodes?.isNotEmpty() == true && actionsOut, Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(horizontal = 16.dp).padding(bottom = 4.dp),
            enter = slideInVertically(DS.panel()) { it } + fadeIn(), exit = slideOutVertically(DS.panel()) { it } + fadeOut()) {
            Row(Modifier.fillMaxWidth().dsBar(32.dp).padding(8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                PillButton(playTitle, Modifier.weight(1f), icon = Icons.Filled.PlayArrow, tone = PillTone.Ink) { onPlay(seriesId, startEp) }
                d?.let { Heart(seriesId, it, 48.dp) }
            }
        }
    }
}

@Composable
private fun DetailHero(d: HGSeriesDetail?, sid: String) {
    val c = IdjThemeColors
    Box(Modifier.fillMaxWidth().height(300.dp)) {
        // `.bd`: the poster blurred 30 dp past the edges; API < 31 falls back to a tiny upscaled thumbnail.
        Box(Modifier.fillMaxSize().clipToBounds()) {
            if (android.os.Build.VERSION.SDK_INT >= 31) AsyncImage(d?.cover, null, Modifier.fillMaxSize().scale(1.35f).blur(30.dp), contentScale = ContentScale.Crop)
            else {
                val ctx = androidx.compose.ui.platform.LocalContext.current
                val req = remember(d?.cover) { coil.request.ImageRequest.Builder(ctx).data(d?.cover).size(16, 22).build() }
                AsyncImage(req, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
            }
        }
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(0f to Color.Black.copy(0.30f), 0.34f to Color.Black.copy(0.08f), 0.76f to c.bg.copy(0.74f), 1f to c.bg)))
        Row(Modifier.align(Alignment.BottomStart).padding(horizontal = 20.dp).padding(bottom = 2.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            val eps = d?.let { "全 ${maxOf(it.totalEps, it.episodes.size)} 集" }
            Box(Modifier.size(116.dp, 155.dp).shadow(15.dp, RoundedCornerShape(12.dp), ambientColor = Color.Black.copy(0.4f), spotColor = Color.Black.copy(0.4f))) {
                PosterArt(d?.cover ?: "", Modifier.fillMaxSize(), corner = 12.dp)
                if (eps != null) Text(eps, Modifier.align(Alignment.BottomCenter).padding(bottom = 8.dp), color = Color.White.copy(0.8f), fontSize = 10.sp)
            }
            Column(Modifier.weight(1f).padding(bottom = 2.dp)) {
                DSStatus(d?.source ?: "红果短剧", StatusTone.Accent)
                Text(d?.title ?: "", color = c.text, fontSize = 23.sp, fontWeight = FontWeight.ExtraBold, maxLines = 2, overflow = TextOverflow.Ellipsis,
                    lineHeight = 29.sp, modifier = Modifier.padding(top = 8.dp))
                val meta = listOfNotNull(d?.let { if (it.episodeLabel.isEmpty()) eps else DS.spaced(it.episodeLabel) }, d?.author?.ifEmpty { null }).joinToString(" · ")
                Text(meta, color = c.secondary, fontSize = 13.sp, maxLines = 1, modifier = Modifier.padding(top = 6.dp))
            }
        }
    }
}

@Composable
private fun Heart(sid: String, d: HGSeriesDetail, size: androidx.compose.ui.unit.Dp) {
    val c = IdjThemeColors
    val lib = IdjApp.instance.library
    val fav = lib.isFavorite(sid)
    val s by animateFloatAsState(if (fav) 1f else 0.9f, DS.press(), label = "heart")
    Box(Modifier.size(size).clip(CircleShape).background(c.glass).border(1.dp, c.hairline, CircleShape)
        .pressClick(label = if (fav) "取消收藏" else "收藏") { lib.toggleFavorite(sid, d.title, d.cover) }, contentAlignment = Alignment.Center) {
        Icon(if (fav) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, null, Modifier.size(22.dp).scale(s / 0.95f), tint = if (fav) c.accent else c.text)
    }
}

@Composable
private fun DetailBody(
    d: HGSeriesDetail, sid: String, resume: app.iduanju.data.WatchProgress?, group: Int, setGroup: (Int) -> Unit,
    onPlay: (String, Int) -> Unit, onOpenSeries: (String) -> Unit, playTitle: String, startEp: Int, onActions: (Float) -> Unit,
) {
    val c = IdjThemeColors
    val ranges = EpisodeGroups.ranges(d.episodes.size)
    val g = if (group in ranges.indices) group else 0
    Stats(d, Modifier.padding(top = 18.dp))
    Row(Modifier.padding(horizontal = 20.dp).padding(top = 16.dp).onGloballyPositioned { onActions(it.boundsInRoot().bottom) },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        PillButton(playTitle, Modifier.weight(1f), icon = Icons.Filled.PlayArrow, tone = PillTone.Ink, height = 50.dp, enabled = d.episodes.isNotEmpty()) { onPlay(sid, startEp) }
        Heart(sid, d, 50.dp)
    }
    if (d.tags.isNotEmpty()) {
        LazyRow(Modifier.padding(top = 16.dp), contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            items(d.tags) { t ->
                Box(Modifier.height(26.dp).clip(CircleShape).background(c.glass).padding(horizontal = 10.dp), contentAlignment = Alignment.Center) {
                    Text(t, color = c.secondary, fontSize = 12.sp)
                }
            }
        }
    }
    if (d.cast.isEmpty() && d.actors.isNotEmpty()) {
        Text("主演：" + d.actors.joinToString(" / "), color = c.secondary, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 20.dp).padding(top = 12.dp))
    }
    if (d.desc.isNotEmpty()) Intro(d.desc)

    // 选集 (moved up, right after the intro)
    SectionHeader2("选集", "共 ${maxOf(d.totalEps, d.episodes.size)} 集", inset = 20.dp, modifier = Modifier.padding(top = 22.dp))
    if (ranges.size > 1) {
        LazyRow(Modifier.padding(top = 12.dp), contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            itemsIndexed(ranges) { i, r -> ToneChip(EpisodeGroups.label(r, d.episodes), i == g, neutral = true, small = true) { setGroup(i) } }
        }
    }
    ranges.getOrNull(g)?.let { r ->
        androidx.compose.animation.AnimatedContent(r, label = "eps", transitionSpec = { fadeIn() togetherWith fadeOut() }) { rr ->
            Column(Modifier.padding(horizontal = 20.dp).padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                rr.chunked(6).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { i ->
                            val ep = d.episodes[i]
                            val cur = resume?.episodeIndex == i
                            Box(Modifier.weight(1f).height(44.dp).clip(RoundedCornerShape(12.dp)).background(if (cur) c.accentSoft else c.glass)
                                .then(if (cur) Modifier.border(1.dp, c.accentLine, RoundedCornerShape(12.dp)) else Modifier)
                                .pressClick(0.94f, label = "第${ep.ep}集") { onPlay(sid, ep.ep) }, contentAlignment = Alignment.Center) {
                                Text("${ep.ep}", color = if (cur) c.accent else c.text, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                                if (cur) Box(Modifier.align(Alignment.TopEnd).padding(6.dp).size(5.dp).clip(CircleShape).background(c.accent))
                            }
                        }
                        repeat(6 - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
    }
    if (d.relatedSeries.size > 1) RelatedShelf(d.relatedSeries, d.seriesId, onOpenSeries)
    if (d.cast.isNotEmpty()) {
        SectionHeader2("演员", inset = 20.dp, modifier = Modifier.padding(top = 24.dp))
        LazyRow(Modifier.padding(top = 12.dp), contentPadding = PaddingValues(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            items(d.cast) { p ->
                Column(Modifier.width(64.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Box(Modifier.size(56.dp).clip(CircleShape).background(Brush.linearGradient(listOf(c.accent.copy(0.5f), c.accentWarm.copy(0.5f)))), contentAlignment = Alignment.Center) {
                        Text(p.name.take(1), color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
                        if (p.avatar.isNotEmpty()) AsyncImage(p.avatar, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    }
                    Text(p.name, color = c.text, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 6.dp))
                    if (p.role.isNotEmpty()) Text(p.role, color = c.secondary, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

@Composable
private fun Stats(d: HGSeriesDetail, modifier: Modifier = Modifier) {
    val c = IdjThemeColors
    data class Cell(val icon: androidx.compose.ui.graphics.vector.ImageVector?, val value: String, val label: String)
    val cells = buildList {
        if (d.rating > 0) add(Cell(Icons.Filled.Star, String.format("%.1f", d.rating), "观众评分" + if (d.ratingCount.isEmpty()) "" else " · " + DS.spaced(d.ratingCount) + "人"))
        if (d.favoriteCount > 0) add(Cell(null, DS.count(d.favoriteCount), "收藏"))
        if (d.hotText.isNotEmpty()) add(Cell(Icons.Filled.LocalFireDepartment, DS.spaced(d.hotText), "全网热度"))
    }
    if (cells.isEmpty()) return
    // A sparse response occupies only its real columns; keep the spec's three-column metric density.
    BoxWithConstraints(modifier.padding(horizontal = 20.dp).fillMaxWidth()) {
      Row(Modifier.width(maxWidth * (cells.size.coerceAtMost(3) / 3f)).height(63.dp).dsCard(16.dp).padding(vertical = 11.dp)) {
        cells.forEachIndexed { i, cell ->
            if (i > 0) Box(Modifier.width(1.dp).fillMaxHeight().background(c.hairline))
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                Row(Modifier.height(22.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    if (cell.icon != null) Icon(cell.icon, null, Modifier.size(14.dp), tint = c.accentWarm)
                    Text(cell.value, color = c.text, fontSize = 17.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                }
                Text(cell.label, color = c.secondary, fontSize = 11.sp, maxLines = 1)
            }
        }
      }
    }
}

/** `.intro`: three lines, 展开 over a fade; tap toggles. */
@Composable
private fun Intro(text: String) {
    val c = IdjThemeColors
    var open by remember { mutableStateOf(false) }
    var clamped by remember { mutableStateOf(false) }
    Box(Modifier.padding(horizontal = 20.dp).padding(top = 14.dp).fillMaxWidth().animateContentSize(DS.panel())
        .clickable(remember { androidx.compose.foundation.interaction.MutableInteractionSource() }, null, enabled = clamped || open) { open = !open }) {
        Text(text, color = c.secondary, fontSize = 14.sp, lineHeight = 22.sp, maxLines = if (open) Int.MAX_VALUE else 3, overflow = TextOverflow.Clip,
            onTextLayout = { if (!open) clamped = it.hasVisualOverflow })
        if (clamped && !open) Text("展开", Modifier.align(Alignment.BottomEnd).background(Brush.horizontalGradient(0f to c.bg.copy(0f), 0.42f to c.bg)).padding(start = 36.dp),
            color = c.accent, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = 22.sp)
    }
}

@Composable
fun SectionHeader(title: String, modifier: Modifier = Modifier, trailing: (@Composable () -> Unit)? = null) {
    val c = IdjThemeColors
    Row(modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = c.text, fontSize = 20.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.weight(1f))
        trailing?.invoke()
    }
}

@Composable
private fun RelatedShelf(items: List<HGSeries>, currentId: String, onOpen: (String) -> Unit) {
    val c = IdjThemeColors
    val go = app.iduanju.ui.LocalNavigate.current
    SectionHeader2("系列", "共 ${items.size} 季", inset = 20.dp, modifier = Modifier.padding(top = 26.dp)) {
        MoreLink("搜全系列", Icons.Filled.Search) { go("actorSearch/" + android.net.Uri.encode(items.firstOrNull { it.seriesId == currentId }?.title ?: "")) }
    }
    LazyRow(Modifier.padding(top = 12.dp), contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 4.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        items(items) { s ->
            val on = s.seriesId == currentId
            Column(Modifier.width(104.dp).pressClick(0.97f, enabled = !on, label = s.title) { onOpen(s.seriesId) }) {
                Box(Modifier.size(104.dp, 139.dp).then(if (on) Modifier.border(2.dp, c.accent, RoundedCornerShape(16.dp)).padding(4.dp) else Modifier)) {
                    PosterArt(s.cover, Modifier.fillMaxSize(), corner = 12.dp)
                    if (on) Box(Modifier.padding(6.dp).height(18.dp).clip(RoundedCornerShape(5.dp)).background(c.accent).padding(horizontal = 6.dp), contentAlignment = Alignment.Center) {
                        Text("当前", color = c.onAccent, fontSize = 10.5.sp, fontWeight = FontWeight.Bold)
                    }
                }
                Text(s.title, color = c.text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp))
                if (s.episodeCount > 0) Text("${s.episodeCount} 集", color = c.secondary, fontSize = 11.sp, maxLines = 1, modifier = Modifier.padding(top = 2.dp))
            }
        }
    }
}
