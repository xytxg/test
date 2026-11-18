package app.iduanju.ui.player

import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.animation.togetherWith
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import app.iduanju.IdjApp
import app.iduanju.core.hongguo.HGSeriesDetail
import app.iduanju.data.WatchProgress
import app.iduanju.ui.theme.IdjThemeColors
import app.iduanju.ui.theme.IdjDarkColors
import app.iduanju.ui.theme.IdjColors
import app.iduanju.ui.components.DS
import app.iduanju.ui.components.pressClick
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.graphicsLayer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerScreen(seriesId: String, startEp: Int, onBack: () -> Unit, onSwitchSeries: (String) -> Unit = {}) {
    val ctx = LocalContext.current
    val lib = IdjApp.instance.library
    var detail by remember { mutableStateOf<HGSeriesDetail?>(null) }
    var epIndex by remember { mutableIntStateOf(-1) }
    var status by remember { mutableStateOf("加载中…") }
    var error by remember { mutableStateOf<String?>(null) }
    val fixture = app.iduanju.BuildConfig.DEBUG && seriesId == "ui-color-bars"
    var centerSuppressed by remember { mutableStateOf(false) }
    var previousEpisode by remember { mutableIntStateOf(-1) }
    var showChrome by remember { mutableStateOf(true) }
    var playing by remember { mutableStateOf(false) }
    var pos by remember { mutableLongStateOf(0L) }
    var dur by remember { mutableLongStateOf(0L) }
    var buffered by remember { mutableLongStateOf(0L) }
    var speed by remember { mutableFloatStateOf(1f) }
    var holdSpeed by remember { mutableStateOf(false) }
    var seekHint by remember { mutableStateOf<String?>(null) }
    /** "episodes" · "speed" · "quality" · "audio"; one panel at a time. */
    var panel by remember { mutableStateOf(if(app.iduanju.BuildConfig.DEBUG)app.iduanju.ui.UiEvidence.panel else null) }
    var danmaku by remember { mutableStateOf(true) }
    var quality by remember { mutableStateOf<String?>(null) }
    var fillMode by remember { mutableStateOf(false) }
    var locked by remember { mutableStateOf(false) }
    var autoNext by remember { mutableStateOf(true) }
    val activity = ctx as? android.app.Activity
    val landscape = androidx.compose.ui.platform.LocalConfiguration.current.orientation == android.content.res.Configuration.ORIENTATION_LANDSCAPE
    fun setLandscape(on: Boolean) {
        activity?.requestedOrientation = if (on) android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE else android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    }
    androidx.activity.compose.BackHandler(enabled = landscape) { setLandscape(false) }
    LaunchedEffect(landscape) {
        val w = activity?.window ?: return@LaunchedEffect
        val ic = androidx.core.view.WindowCompat.getInsetsController(w, w.decorView)
        ic.systemBarsBehavior = androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (landscape) ic.hide(androidx.core.view.WindowInsetsCompat.Type.systemBars()) else ic.show(androidx.core.view.WindowInsetsCompat.Type.systemBars())
    }
    var tags by remember { mutableStateOf(TechTags()) }
    var retry by remember { mutableIntStateOf(0) }

    // OkHttp (HTTP/2) like iOS URLSession: huangguo.video's Cloudflare 403s HTTP/1.1 (HttpURLConnection),
    // which made every 黄果 视频站 segment request fail with ERROR_CODE_IO_BAD_HTTP_STATUS.
    val httpFactory = remember { androidx.media3.datasource.okhttp.OkHttpDataSource.Factory(EpisodeCache.http).setUserAgent(app.iduanju.core.cms.MacCMS.UA) }
    val player = remember {
        ExoPlayer.Builder(ctx).setMediaSourceFactory(
            androidx.media3.exoplayer.source.DefaultMediaSourceFactory(androidx.media3.datasource.DefaultDataSource.Factory(ctx, httpFactory))
        ).build().also { it.playWhenReady = true }
    }
    DisposableEffect(Unit) {
        val l = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED && autoNext) {
                    val n = detail?.episodes?.size ?: 0
                    if (epIndex + 1 < n) epIndex += 1
                }
            }
            override fun onPlayerError(e: PlaybackException) { error = "播放失败：${e.errorCodeName}"; keepScreenOn(activity, false) }
            // Keep the display awake only while frames are actually playing (portrait, landscape, same activity window).
            override fun onIsPlayingChanged(isPlaying: Boolean) { keepScreenOn(activity, isPlaying) }
            override fun onTracksChanged(t: androidx.media3.common.Tracks) {
                tags = TechTags.from(player, quality)
            }
            // videoFormat/audioFormat are populated once the renderers start, after onTracksChanged
            override fun onRenderedFirstFrame() { tags = TechTags.from(player, quality) }
            override fun onVideoSizeChanged(videoSize: androidx.media3.common.VideoSize) { tags = TechTags.from(player, quality) }
        }
        player.addListener(l)
        onDispose { keepScreenOn(activity, false); player.removeListener(l); player.release() }
    }

    LaunchedEffect(seriesId) {
        if(fixture) {
            detail=HGSeriesDetail(seriesId=seriesId,title="本地彩条测试 · 非真实片源",totalEps=48,source="本地测试",
                episodes=(1..48).map{app.iduanju.core.hongguo.HGEpisode(it,"fixture-$it",60,"彩条第 $it 段")})
            epIndex=startEp.coerceIn(0,47)
            if(app.iduanju.ui.UiEvidence.landscape)setLandscape(true)
            return@LaunchedEffect
        }
        try {
            val d = withContext(Dispatchers.IO) { app.iduanju.data.Catalog.detail(seriesId, web = false) }
            detail = d
            epIndex = d.episodes.indexOfFirst { it.ep == startEp }.coerceAtLeast(0)
        } catch (e: Exception) { error = e.message ?: "详情失败"; status = "" }
    }

    LaunchedEffect(detail, epIndex, retry) {
        val d = detail ?: return@LaunchedEffect
        val ep = d.episodes.getOrNull(epIndex) ?: return@LaunchedEffect
        if(previousEpisode >= 0 && previousEpisode != epIndex) centerSuppressed=true
        previousEpisode=epIndex
        error = null; status = "取流中…"
        player.stop(); player.clearMediaItems()
        if(fixture) {
            val local=java.io.File(ctx.cacheDir,"ui-color-bars.mp4")
            if(!local.exists())withContext(Dispatchers.IO){ctx.assets.open("player_landscape.mp4").use{input->local.outputStream().use{input.copyTo(it)}}}
            player.setMediaItem(MediaItem.fromUri(android.net.Uri.fromFile(local)))
            status="";player.prepare();player.play()
            return@LaunchedEffect
        }
        try {
            val p = EpisodeCache.get(ep) { status = it }.await()
            quality = p.quality
            status = ""
            // plugin / 采集站 streams may need Referer/Origin/UA on every segment request
            httpFactory.setUserAgent(p.headers.entries.firstOrNull { it.key.equals("user-agent", true) }?.value ?: app.iduanju.core.cms.MacCMS.UA)
            httpFactory.setDefaultRequestProperties(p.headers.filterKeys { !it.equals("user-agent", true) })
            player.setMediaItem(
                MediaItem.Builder().setUri(if (p.uri.startsWith("/")) android.net.Uri.fromFile(java.io.File(p.uri)) else android.net.Uri.parse(p.uri))
                    .apply { if (p.hls) setMimeType(androidx.media3.common.MimeTypes.APPLICATION_M3U8) }.build()
            )
            p.note?.let { android.util.Log.i("IDJ", "hls: $it") }
            player.setPlaybackSpeed(speed)
            val resume = lib.progress(seriesId)
            if (resume != null && resume.episodeIndex == epIndex && resume.seconds > 3 && resume.fraction < 0.95f) player.seekTo((resume.seconds * 1000).toLong())
            player.prepare(); player.play()
            // precache next episode (iOS preloads the next stream while this one plays)
            // spaced ≥6 s from the current resolve: fresh one-shot registrations back-to-back get soft-rejected (probe 2026-11-11)
            if (IdjApp.instance.settings.prefetchEnabled) d.episodes.getOrNull(epIndex + 1)?.let { delay(6_000); EpisodeCache.preload(it) }
        } catch (e: Exception) {
            status = ""; error = e.message ?: "播放失败"
        }
    }

    LaunchedEffect(fixture) {
        if(fixture && app.iduanju.ui.UiEvidence.switchEpisode) { delay(6000); epIndex=(epIndex+1)%48 }
    }
    LaunchedEffect(player) {
        var tick = 0
        while (isActive) {
            pos = player.currentPosition; dur = player.duration.coerceAtLeast(0); buffered = player.bufferedPosition
            playing = player.isPlaying
            if (++tick % 20 == 0 && playing) detail?.let { d ->
                d.episodes.getOrNull(epIndex)?.let { ep ->
                    lib.record(WatchProgress(seriesId, d.title, d.cover, epIndex, ep.ep, pos / 1000.0, dur / 1000.0, System.currentTimeMillis()))
                }
            }
            delay(250)
        }
    }
    LaunchedEffect(showChrome, playing, panel) { if (showChrome && playing && panel == null && !(app.iduanju.BuildConfig.DEBUG && app.iduanju.ui.UiEvidence.keepChrome)) { delay(4000); showChrome = false } }
    LaunchedEffect(seekHint) { if (seekHint != null) { delay(700); seekHint = null } }
    DisposableEffect(Unit) {
        onDispose {
            activity?.requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
            activity?.window?.let { w -> androidx.core.view.WindowCompat.getInsetsController(w, w.decorView).show(androidx.core.view.WindowInsetsCompat.Type.systemBars()) }
            detail?.let { d -> d.episodes.getOrNull(epIndex)?.let { ep ->
                lib.record(WatchProgress(seriesId, d.title, d.cover, epIndex, ep.ep, pos / 1000.0, dur / 1000.0, System.currentTimeMillis()))
            } }
        }
    }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        AndroidView(
            factory = {
                PlayerView(it).apply {
                    useController = false
                    setShutterBackgroundColor(android.graphics.Color.BLACK)
                    layoutParams = FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    this.player = player
                }
            },
            update = { view ->
                view.resizeMode = if (fillMode) AspectRatioFrameLayout.RESIZE_MODE_ZOOM else AspectRatioFrameLayout.RESIZE_MODE_FIT
                if (app.iduanju.BuildConfig.DEBUG) {
                    // Inspect Media3's actual SurfaceView, not the Compose/PlayerView wrapper.
                    val controls = showChrome
                    view.postDelayed({
                        val surface = view.videoSurfaceView
                        val rect = android.graphics.Rect()
                        surface?.getGlobalVisibleRect(rect)
                        val value = "controls=$controls surface=$rect bounds=${surface?.width}x${surface?.height} viewport=${view.width}x${view.height}"
                        android.util.Log.i("IDJ_RENDER", value)
                    }, 250)
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
        // official danmaku (红果 only), lanes under the top bar + tech strip, never into the bottom controls
        val epNow = detail?.episodes?.getOrNull(epIndex)
        if (danmaku && epNow != null && seriesId.all { it.isDigit() }) {
            val topInset = with(androidx.compose.ui.platform.LocalDensity.current) { androidx.compose.foundation.layout.WindowInsets.statusBars.getTop(this).toDp() }
            DanmakuOverlay(player, seriesId, epNow.vid, laneTop = topInset + 44.dp + 34.dp, bottomLimit = 220.dp) { android.util.Log.i("IDJ", "danmaku: $it") }
        }
        // gesture layer: tap = chrome, double-tap sides = ±10s, long-press = 2x, vertical swipe = prev/next episode,
        // horizontal drag = scrub.
        Box(
            Modifier.fillMaxSize()
                .pointerInput(Unit) {
                    detectTapGestures(
                        onTap = { if(locked) showChrome=true else if (panel != null) panel = null else if(centerSuppressed) {centerSuppressed=false;showChrome=true} else showChrome = !showChrome },
                        onDoubleTap = doubleTap@ { o ->
                            if(locked)return@doubleTap
                            val w = size.width
                            when {
                                o.x < w / 3 -> { player.seekTo((player.currentPosition - 10_000).coerceAtLeast(0)); seekHint = "-10s" }
                                o.x > w * 2 / 3 -> { player.seekTo(player.currentPosition + 10_000); seekHint = "+10s" }
                                else -> if (player.isPlaying) player.pause() else player.play()
                            }
                        },
                        onPress = {
                            val ok = tryAwaitRelease()
                            if (holdSpeed) { holdSpeed = false; player.setPlaybackSpeed(speed) }
                            ok
                        },
                        onLongPress = { if(!locked){holdSpeed = true; player.setPlaybackSpeed(2f)} },
                    )
                }
                .pointerInput(detail) {
                    var acc = 0f
                    detectVerticalDragGestures(onDragStart = { acc = 0f }, onDragEnd = {
                        val n = detail?.episodes?.size ?: 0
                        if (!locked && acc < -160 && epIndex + 1 < n) epIndex += 1
                        else if (!locked && acc > 160 && epIndex > 0) epIndex -= 1
                    }) { _, d -> acc += d }
                }
                .pointerInput(Unit) {
                    var start = 0L; var acc = 0f
                    detectHorizontalDragGestures(onDragStart = { start = player.currentPosition; acc = 0f }, onDragEnd = {
                        if(!locked)player.seekTo((start + (acc / size.width * 90_000).toLong()).coerceIn(0, player.duration.coerceAtLeast(0)))
                        seekHint = null
                    }) { _, d ->
                        acc += d
                        val t = (start + (acc / size.width * 90_000).toLong()).coerceIn(0, player.duration.coerceAtLeast(0))
                        seekHint = fmt(t) + " / " + fmt(player.duration.coerceAtLeast(0))
                    }
                },
        )

        if (status.isNotEmpty() && error == null) {
            Column(Modifier.align(Alignment.Center), horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator(color = Color.White, strokeWidth = 2.dp, modifier = Modifier.size(28.dp))
                Spacer(Modifier.height(12.dp))
                Text(status, color = Color.White.copy(0.8f), fontSize = 13.sp)
            }
        }
        error?.let {
            Column(Modifier.align(Alignment.Center).padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(it, color = Color.White.copy(0.85f), fontSize = 14.sp)
                Spacer(Modifier.height(14.dp))
                Text("重试", color = Color.Black, fontWeight = FontWeight.SemiBold, fontSize = 14.sp,
                    modifier = Modifier.clip(RoundedCornerShape(50)).background(Color.White).clickable { retry++ }.padding(horizontal = 18.dp, vertical = 8.dp))
            }
        }
        if (holdSpeed) {
            Row(Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 96.dp).clip(RoundedCornerShape(16.dp)).background(Color.Black.copy(0.55f))
                .padding(horizontal = 22.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.FastForward, null, tint = Color.White); Spacer(Modifier.width(8.dp))
                Text("2.0×", color = Color.White, fontSize = 24.sp, fontWeight = FontWeight.Bold)
            }
        }
        seekHint?.let {
            Text(it, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.align(Alignment.Center).offset(y = (-90).dp).clip(RoundedCornerShape(12.dp)).background(Color.Black.copy(0.55f)).padding(horizontal = 16.dp, vertical = 8.dp))
        }

        // ── Chrome (redesign 14–17) ─────────────────────────────────────────────────────────────────────
        // Compact title + 2dp edge progress stay visible; full controls are independent overlays. The centre transport
        // only appears once the current episode is actually playable, so switching episodes never flashes it.
        val pc = IdjDarkColors
        val chromeA by androidx.compose.animation.core.animateFloatAsState(if (showChrome || panel != null) 1f else 0f, DS.panel(), label = "chrome")
        val ready = status.isEmpty() && error == null && dur > 0
        Box(Modifier.fillMaxWidth().height(if(landscape)72.dp else 110.dp).graphicsLayer { alpha = chromeA }
            .background(Brush.verticalGradient(listOf(Color.Black.copy(0.45f), Color.Black.copy(0.16f), Color.Transparent))))
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(if(landscape)100.dp else 150.dp).graphicsLayer { alpha = chromeA }
            .background(Brush.verticalGradient(0f to Color.Transparent, 0.42f to Color.Black.copy(0.16f), 1f to Color.Black.copy(0.45f))))
        Column(Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = if(landscape)64.dp else 16.dp).padding(top = if(landscape)14.dp else 6.dp).graphicsLayer { alpha = chromeA }) {
            Row(Modifier.height(44.dp), verticalAlignment = Alignment.CenterVertically) {
                CircleBtn(Icons.AutoMirrored.Filled.ArrowBackIos, "返回", showChrome && !locked, onBack)
                if(landscape) {
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text(detail?.title.orEmpty(),color=Color.White,fontSize=16.sp,fontWeight=FontWeight.Bold,maxLines=1,overflow=androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                        Text("第 ${detail?.episodes?.getOrNull(epIndex)?.ep ?: 1} 集 / 共 ${detail?.episodes?.size ?: 0} 集",color=Color.White.copy(0.7f),fontSize=12.sp)
                    }
                    TechLine(tags,Modifier.padding(end=14.dp))
                    LandChip(Icons.Filled.Repeat,"连播",if(autoNext)"开" else "关",autoNext,showChrome&&!locked){autoNext=!autoNext}
                    Spacer(Modifier.width(10.dp))
                    CircleBtn(if(locked)Icons.Filled.Lock else Icons.Filled.LockOpen,if(locked)"解锁" else "锁屏",showChrome){locked=!locked}
                    Spacer(Modifier.width(10.dp))
                    CircleBtn(Icons.Filled.FullscreenExit,"退出横屏",showChrome&&!locked){setLandscape(false)}
                } else {
                    Spacer(Modifier.weight(1f))
                    CircleBtn(Icons.Filled.PictureInPictureAlt, "画中画", showChrome) {}
                    Spacer(Modifier.width(10.dp))
                    val fav = lib.isFavorite(seriesId)
                    CircleBtn(if (fav) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder, "收藏", showChrome) {
                        detail?.let { lib.toggleFavorite(seriesId, it.title, it.cover) }
                    }
                    Spacer(Modifier.width(10.dp))
                    CircleBtn(Icons.Filled.MoreHoriz, "更多", showChrome) { fillMode = !fillMode }
                }
            }
            if (!landscape) TechLine(tags, Modifier.fillMaxWidth().padding(top = 6.dp))
        }
        androidx.compose.animation.AnimatedVisibility(showChrome && ready && !centerSuppressed && !locked && panel == null, Modifier.align(Alignment.Center),
            enter = fadeIn(DS.panel()) + androidx.compose.animation.scaleIn(DS.panel(), initialScale = 0.92f),
            exit = fadeOut(DS.panel()) + androidx.compose.animation.scaleOut(DS.panel(), targetScale = 0.92f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(if(landscape)72.dp else 44.dp)) {
                Icon(Icons.Filled.Replay10, "后退10秒", tint = Color.White, modifier = Modifier.size(36.dp).pressClick(0.9f) { player.seekTo((player.currentPosition - 10_000).coerceAtLeast(0)) })
                Box(Modifier.size(68.dp).clip(CircleShape).background(Color(0x7514141A)).border(1.dp, Color.White.copy(0.18f), CircleShape)
                    .pressClick(0.92f, label = if (playing) "暂停" else "播放") { if (player.isPlaying) player.pause() else player.play() },
                    contentAlignment = Alignment.Center) {
                    androidx.compose.animation.Crossfade(playing, label = "pp") { p ->
                        Icon(if (p) Icons.Filled.Pause else Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.size(32.dp))
                    }
                }
                Icon(Icons.Filled.Forward10, "前进10秒", tint = Color.White, modifier = Modifier.size(36.dp).pressClick(0.9f) { player.seekTo(player.currentPosition + 10_000) })
            }
        }
        // Expanded bottom controls overlay the video; never reserve space in its viewport.
        if (showChrome || panel != null) Column(Modifier.align(Alignment.BottomStart).fillMaxWidth().navigationBarsPadding().graphicsLayer { alpha = chromeA }
            .padding(horizontal = if (landscape) 64.dp else 20.dp).padding(bottom = if (landscape) 24.dp else 4.dp)) {
            val d = detail
            if (d != null && !landscape) {
                Row(Modifier.graphicsLayer { alpha = chromeA }.heightIn(min = 28.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(d.source, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(Color.White.copy(0.16f)).padding(horizontal = 7.dp, vertical = 2.dp))
                    Spacer(Modifier.width(8.dp))
                    val seasonTag = remember(d.relatedSeries) {
                        val ss = d.relatedSeries
                        val nums = ss.map { app.iduanju.core.hongguo.SeasonParser.seasonNo(it.title) }
                        if (ss.size > 1 && nums.toSet().size == ss.size)
                            "第 " + app.iduanju.core.hongguo.SeasonParser.seasonNo(ss.firstOrNull { it.seriesId == d.seriesId }?.title ?: d.title) + " 季" else null
                    }
                    seasonTag?.let { Text("$it · ", color = Color.White.copy(0.72f), fontSize = 13.sp) }
                    Text("第 ${d.episodes.getOrNull(epIndex)?.ep ?: startEp} 集", color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    Text(" / 共 ${maxOf(d.totalEps, d.episodes.size)} 集", color = Color.White.copy(0.72f), fontSize = 13.sp)
                }
                Spacer(Modifier.height(8.dp))
                Text(d.title, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 21.sp, lineHeight = 27.sp, maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                    style = androidx.compose.ui.text.TextStyle(shadow = androidx.compose.ui.graphics.Shadow(Color.Black.copy(0.7f), blurRadius = 6f)))
            }
            Spacer(Modifier.height(10.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                val tStyle = androidx.compose.ui.text.TextStyle(color = Color.White.copy(0.8f), fontSize = 12.sp, fontWeight = FontWeight.Medium,
                    fontFeatureSettings = "tnum", shadow = androidx.compose.ui.graphics.Shadow(Color.Black.copy(0.6f), blurRadius = 4f))
                Text(fmt(pos), style = tStyle)
                Spacer(Modifier.width(10.dp))
                Box(Modifier.weight(1f)) { ProgressBar(pos, dur, buffered) { if(!locked){player.seekTo(it); showChrome = true} } }
                Spacer(Modifier.width(10.dp))
                Text(if (dur > 0) "−" + fmt(dur - pos) else "−0:00", style = tStyle)
                if (!landscape) {
                    Spacer(Modifier.width(10.dp))
                    Icon(Icons.Filled.Fullscreen, "横屏全屏", tint = Color.White,
                        modifier = Modifier.size(24.dp).pressClick(0.9f) { setLandscape(true) })
                }
            }
            if(landscape) Row(Modifier.fillMaxWidth().padding(top=6.dp).graphicsLayer{alpha=if(locked)0f else chromeA},verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(8.dp)) {
                if(pos<15000&&dur>45000) LandChip(Icons.Filled.PlayArrow,"跳过片头",null,false,showChrome&&!locked){player.seekTo(15000)}
                Spacer(Modifier.weight(1f))
                LandChip(Icons.Filled.GridView,"选集",null,panel=="episodes",showChrome&&!locked){panel=if(panel=="episodes")null else "episodes"}
                LandChip(Icons.Filled.Speed,"倍速",if(speed==1f)"1.0×" else "${speed}×",panel=="speed",showChrome&&!locked){panel=if(panel=="speed")null else "speed"}
                LandChip(Icons.Filled.HighQuality,"画质",quality?:tags.res,panel=="quality",showChrome&&!locked){panel=if(panel=="quality")null else "quality"}
                LandChip(Icons.Filled.Subtitles,"弹幕",if(seriesId.all{it.isDigit()}) (if(danmaku)"开" else "关") else null,danmaku&&seriesId.all{it.isDigit()},showChrome&&!locked&&seriesId.all{it.isDigit()}){danmaku=!danmaku}
                LandChip(Icons.Filled.ClosedCaption,"音轨字幕",null,panel=="audio",showChrome&&!locked){panel=if(panel=="audio")null else "audio"}
            } else Row(Modifier.fillMaxWidth().padding(top = 10.dp).graphicsLayer { alpha = chromeA }.padding(horizontal = if (landscape) 120.dp else 0.dp)) {
                val dmOK = seriesId.all { it.isDigit() }
                val on = showChrome
                ActionBtn(Icons.Filled.GridView, "选集", null, panel == "episodes", false, on) { panel = if (panel == "episodes") null else "episodes" }
                ActionBtn(Icons.Filled.Speed, "倍速", if (speed == 1f) "1.0×" else "${speed}×".replace(".0×", "×"), panel == "speed", speed != 1f, on) { panel = if (panel == "speed") null else "speed" }
                ActionBtn(Icons.Filled.HighQuality, "画质", quality ?: tags.res, panel == "quality", false, on) { panel = if (panel == "quality") null else "quality" }
                ActionBtn(Icons.Filled.Subtitles, "弹幕", if (dmOK) (if (danmaku) "开" else "关") else null, false, dmOK && danmaku, on) { if (dmOK) danmaku = !danmaku }
                ActionBtn(Icons.Filled.ClosedCaption, "音轨字幕", null, panel == "audio", false, on) { panel = if (panel == "audio") null else "audio" }
            }

        }
        // Always-on title + edge progress are overlays, not a layout inset or a scrubber row.
        if (!showChrome && panel == null) {
            Text(detail?.title.orEmpty(), color = Color.White.copy(0.85f), fontSize = 12.sp,
                fontWeight = FontWeight.Medium, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                style = androidx.compose.ui.text.TextStyle(shadow = androidx.compose.ui.graphics.Shadow(Color.Black.copy(0.7f), blurRadius = 4f)),
                modifier = Modifier.align(Alignment.TopStart).statusBarsPadding().padding(horizontal = if (landscape) 28.dp else 16.dp, vertical = 10.dp))
            Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(2.dp).background(Color.White.copy(0.18f))) {
                Box(Modifier.fillMaxWidth(if (dur > 0) (pos.toFloat() / dur).coerceIn(0f, 1f) else 0f).fillMaxHeight().background(Color.White.copy(0.6f)))
            }
        }
        // panels: one style for 选集 / 倍速 / 画质 / 音轨字幕, sitting just above the action row
        if (panel != null) Box(Modifier.fillMaxSize().pointerInput(Unit) { detectTapGestures { panel = null } })
        androidx.compose.animation.AnimatedVisibility(panel != null, Modifier.align(Alignment.BottomCenter).navigationBarsPadding()
            .padding(horizontal = 12.dp).padding(bottom = if (landscape) 16.dp else 78.dp),
            enter = fadeIn(DS.panel()) + androidx.compose.animation.slideInVertically(DS.panel()) { it / 6 },
            exit = fadeOut(DS.panel()) + androidx.compose.animation.slideOutVertically(DS.panel()) { it / 6 }) {
            val last = remember { arrayOfNulls<String>(1) }
            if (panel != null) last[0] = panel
            val shown = last[0]
            Column(Modifier.fillMaxWidth().widthIn(max = 520.dp).clip(RoundedCornerShape(24.dp)).background(Color(0xF51C1E24))
                .border(1.dp, Color.White.copy(0.12f), RoundedCornerShape(24.dp)).pointerInput(Unit) { detectTapGestures { } }
                .padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 14.dp)) {
                when (shown) {
                    "episodes" -> detail?.let { d -> EpisodesPanel(d, epIndex, pc, onPick = { epIndex = it; panel = null },
                        onSeason = { id -> panel = null; onSwitchSeries(id) }) }
                    "speed" -> {
                        PanelTitle("倍速", "长按画面临时 2×")
                        Spacer(Modifier.height(8.dp))
                        listOf(0.75f, 1f, 1.25f, 1.5f, 2f, 3f).forEach { s ->
                            PanelRow(if (s == 1f) "1.0× 正常速度" else "${s}×".replace(".0×", "×"), "", s == speed, pc) {
                                speed = s; player.setPlaybackSpeed(s); panel = null
                            }
                        }
                    }
                    "quality" -> {
                        PanelTitle("画质", null)
                        Spacer(Modifier.height(8.dp))
                        val q = quality ?: tags.res ?: "自动"
                        PanelRow(q, player.videoFormat?.let { "${it.width}×${it.height}" } ?: "", true, pc) { panel = null }
                        Text("播放源", color = Color.White.copy(0.55f), fontSize = 12.sp, modifier = Modifier.padding(start = 2.dp, top = 14.dp, bottom = 8.dp))
                        PanelRow(detail?.source ?: "当前片源", "当前", true, pc) { panel = null }
                    }
                    else -> {
                        PanelTitle("音轨字幕", null)
                        Text("音轨", color = Color.White.copy(0.55f), fontSize = 12.sp, modifier = Modifier.padding(start = 2.dp, top = 14.dp, bottom = 8.dp))
                        PanelRow(tags.audio ?: "默认音轨", "", true, pc) { panel = null }
                        Text("字幕", color = Color.White.copy(0.55f), fontSize = 12.sp, modifier = Modifier.padding(start = 2.dp, top = 14.dp, bottom = 8.dp))
                        PanelRow("关闭", "当前视频没有可选字幕", true, pc) { panel = null }
                    }
                }
            }
        }

    }
}

data class TechTags(val res: String? = null, val range: String? = null, val codec: String? = null, val audio: String? = null, val fps: Int? = null) {
    companion object {
        fun from(p: ExoPlayer, quality: String?): TechTags {
            val v = p.videoFormat; val a = p.audioFormat
            val res = quality?.uppercase() ?: v?.let { f -> val h = minOf(f.width, f.height); if (h > 0) "${h}P" else null }
            val codec = v?.sampleMimeType?.let { when { it.contains("hevc") -> "HEVC"; it.contains("avc") -> "H.264"; it.contains("av01") -> "AV1"; else -> null } }
            val range = if (v?.colorInfo?.colorTransfer == androidx.media3.common.C.COLOR_TRANSFER_ST2084 || v?.colorInfo?.colorTransfer == androidx.media3.common.C.COLOR_TRANSFER_HLG) "HDR" else "SDR"
            val audio = a?.let { f -> val n = when { f.sampleMimeType?.contains("mp4a") == true -> "AAC"; f.sampleMimeType?.contains("eac3") == true -> "E-AC-3"; else -> "音频" }
                if (f.channelCount > 0) "$n ${f.channelCount}.0" else n }
            val fps = v?.frameRate?.takeIf { it > 0 }?.let { Math.round(it) }
            return TechTags(res, if (v != null) range else null, codec, audio, fps)
        }
    }
}

/** spec `.tech`: one small centred line instead of a row of badges. */
@Composable
private fun TechLine(t: TechTags, modifier: Modifier = Modifier) {
    val parts = listOfNotNull(t.res, t.range, t.codec, t.audio, t.fps?.let { "$it fps" })
    if (parts.isEmpty()) return
    Text(parts.joinToString(" · "), modifier = modifier, color = Color.White.copy(0.55f), fontSize = 11.sp, fontWeight = FontWeight.Medium,
        letterSpacing = 0.3.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
}

@Composable
private fun CircleBtn(icon: ImageVector, label: String, enabled: Boolean = true, onClick: () -> Unit) {
    // spec `.pbtn`: 40 dp, rgba(20,20,24,.42) + white 14 % hairline
    Box(Modifier.size(40.dp).clip(CircleShape).background(Color(0x6B141418)).border(1.dp, Color.White.copy(0.14f), CircleShape)
        .pressClick(0.92f, enabled = enabled, label = label, onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = Color.White, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun LandChip(icon:ImageVector,title:String,value:String?,on:Boolean,enabled:Boolean,onClick:()->Unit){
    val pc=IdjDarkColors
    Row(Modifier.height(34.dp).graphicsLayer { alpha = if(enabled)1f else 0.45f }.clip(CircleShape).background(if(on)pc.accentSoft else Color(0x75141418))
        .border(1.dp,if(on)pc.accentLine else Color.White.copy(0.14f),CircleShape).pressClick(enabled=enabled,onClick=onClick).padding(horizontal=13.dp),
        verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(6.dp)){
        Icon(icon,null,tint=if(on)pc.accent else Color.White,modifier=Modifier.size(17.dp))
        Text(title+(value?.let{" $it"}?:""),color=if(on)pc.accent else Color.White.copy(0.8f),fontSize=13.sp,maxLines=1,softWrap=false)
    }
}

/** spec `.pact`: 23 dp icon over an 11 sp caption that carries the current value. */
@Composable
private fun RowScope.ActionBtn(icon: ImageVector, title: String, value: String?, active: Boolean, accent: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val pc = IdjDarkColors
    val bg by androidx.compose.animation.animateColorAsState(if (active) Color.White.copy(0.15f) else Color.Transparent, DS.select(), label = "pact")
    Column(Modifier.weight(1f).clip(RoundedCornerShape(14.dp)).background(bg).pressClick(enabled = enabled, label = title, onClick = onClick)
        .padding(top = 7.dp, bottom = 6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(icon, title, tint = if (accent) pc.accent else Color.White, modifier = Modifier.size(23.dp))
        Spacer(Modifier.height(4.dp))
        Text(androidx.compose.ui.text.buildAnnotatedString {
            append(title)
            if (value != null) {
                append(" ")
                pushStyle(androidx.compose.ui.text.SpanStyle(fontWeight = FontWeight.SemiBold, color = if (accent) pc.accent else Color.White)); append(value); pop()
            }
        }, color = Color.White.copy(0.72f), fontSize = 11.sp, lineHeight = 14.sp, maxLines = 1, softWrap = false)
    }
}

@Composable
private fun PanelTitle(title: String, trailing: String?) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
        Text(title, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
        trailing?.let { Text(it, color = Color.White.copy(0.6f), fontSize = 12.sp) }
    }
}

/** spec `.prow`: 46 dp, value right-aligned; current row accent-soft with accent text and ✓. */
@Composable
private fun PanelRow(title: String, detail: String, on: Boolean, pc: IdjColors, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().height(46.dp).clip(RoundedCornerShape(12.dp)).background(if (on) pc.accentSoft else Color.Transparent)
        .pressClick(0.98f, onClick = onClick).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = if (on) pc.accent else Color.White, fontSize = 15.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal, modifier = Modifier.weight(1f))
        if (detail.isNotEmpty()) Text(detail, color = if (on) pc.accent.copy(0.8f) else Color.White.copy(0.55f), fontSize = 12.sp)
        if (on) { Spacer(Modifier.width(10.dp)); Icon(Icons.Filled.Check, null, tint = pc.accent, modifier = Modifier.size(18.dp)) }
    }
}

@Composable
private fun EpisodesPanel(d: HGSeriesDetail, epIndex: Int, pc: IdjColors, onPick: (Int) -> Unit, onSeason: (String) -> Unit) {
    val total = d.episodes.size
    PanelTitle("选集", "共 ${maxOf(total, d.totalEps)} 集 · 更新至 ${d.episodes.lastOrNull()?.ep ?: total} 集")
    val seasons = remember(d.relatedSeries) {
        d.relatedSeries.map { it to app.iduanju.core.hongguo.SeasonParser.seasonNo(it.title) }.distinctBy { it.second }.sortedByDescending { it.second }
    }
    val chip: @Composable (String, Boolean, Boolean, () -> Unit) -> Unit = { t, on, sm, f ->
        Box(Modifier.height(if (sm) 28.dp else 32.dp).clip(RoundedCornerShape(50)).background(if (on) pc.thumb else pc.glass)
            .pressClick(onClick = f).padding(horizontal = if (sm) 12.dp else 14.dp), contentAlignment = Alignment.Center) {
            Text(t, color = if (on) pc.text else pc.secondary, fontSize = if (sm) 13.sp else 14.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal)
        }
    }
    if (seasons.size > 1) Row(Modifier.fillMaxWidth().padding(top = 14.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        seasons.forEach { (s, n) -> chip("第 $n 季", s.seriesId == d.seriesId, false) { if (s.seriesId != d.seriesId) onSeason(s.seriesId) } }
    }
    var range by remember { mutableIntStateOf((epIndex / 30).coerceAtLeast(0)) }
    if (total > 30) Row(Modifier.fillMaxWidth().padding(top = 10.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        (0..(total - 1) / 30).forEach { r -> chip("${d.episodes[r * 30].ep}-${d.episodes[minOf(total - 1, r * 30 + 29)].ep}", r == range, true) { range = r } }
    }
    val slice = d.episodes.withIndex().toList().drop(range * 30).take(30)
    androidx.compose.animation.AnimatedContent(slice, label = "eps", transitionSpec = { fadeIn(DS.select()) togetherWith fadeOut(DS.select()) }) { sl ->
        LazyVerticalGrid(GridCells.Fixed(6), Modifier.heightIn(max = 300.dp).padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(sl.size) { k ->
                val (i, ep) = sl[k]
                val on = i == epIndex
                Box(Modifier.height(44.dp).clip(RoundedCornerShape(12.dp)).background(if (on) pc.accentSoft else pc.glass)
                    .then(if (on) Modifier.border(1.dp, pc.accentLine, RoundedCornerShape(12.dp)) else Modifier)
                    .pressClick { onPick(i) }, contentAlignment = Alignment.Center) {
                    Text("${ep.ep}", color = if (on) pc.accent else Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    if (on) Box(Modifier.align(Alignment.TopEnd).padding(6.dp).size(5.dp).clip(CircleShape).background(pc.accent))
                }
            }
        }
    }
}

/** spec `.ptrack`: 4 dp track, buffered white 30 %, 14 dp round knob; grows while dragging. Tap/drag to seek. */
@Composable
private fun ProgressBar(pos: Long, dur: Long, buffered: Long, onSeek: (Long) -> Unit) {
    var drag by remember { mutableStateOf<Float?>(null) }
    val frac = drag ?: if (dur > 0) pos.toFloat() / dur else 0f
    val buf = if (dur > 0) buffered.toFloat() / dur else 0f
    val h by androidx.compose.animation.core.animateDpAsState(if (drag != null) 8.dp else 4.dp, DS.press(), label = "trk")
    val knob by androidx.compose.animation.core.animateDpAsState(if (drag != null) 20.dp else 14.dp, DS.press(), label = "knob")
    BoxWithConstraints(Modifier.fillMaxWidth().height(28.dp)
        .pointerInput(dur) { detectTapGestures { o -> if (dur > 0) onSeek((o.x / size.width * dur).toLong()) } }
        .pointerInput(dur) {
            detectHorizontalDragGestures(onDragEnd = { drag?.let { if (dur > 0) onSeek((it * dur).toLong()) }; drag = null }) { ch, _ ->
                drag = (ch.position.x / size.width).coerceIn(0f, 1f)
            }
        }, contentAlignment = Alignment.CenterStart) {
        val w = maxWidth
        Box(Modifier.fillMaxWidth().height(h).clip(RoundedCornerShape(50)).background(Color.White.copy(0.24f)))
        Box(Modifier.width(w * buf.coerceIn(0f, 1f)).height(h).clip(RoundedCornerShape(50)).background(Color.White.copy(0.30f)))
        Box(Modifier.width(w * frac.coerceIn(0f, 1f)).height(h).clip(RoundedCornerShape(50)).background(Color.White))
        Box(Modifier.offset(x = (w * frac.coerceIn(0f, 1f)) - knob / 2).size(knob)
            .shadow(3.dp, CircleShape).clip(CircleShape).background(Color.White))
    }
}

private fun fmt(ms: Long): String {
    val s = (ms / 1000).toInt(); val h = s / 3600; val m = s / 60 % 60; val r = s % 60
    return if (h > 0) "%d:%02d:%02d".format(h, m, r) else "%d:%02d".format(m, r)
}


/** FLAG_KEEP_SCREEN_ON on the hosting window while video plays; cleared on pause, end, error and leaving the player. */
internal fun keepScreenOn(activity: android.app.Activity?, on: Boolean) {
    val w = activity?.window ?: return
    if (on) w.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    else w.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    android.util.Log.i("IDJ", "keepScreenOn=$on")
}
