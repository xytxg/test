package app.iduanju.novel

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.luminance
import androidx.core.view.WindowCompat
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.iduanju.core.novel.*
import app.iduanju.ui.theme.IdjThemeColors
import coil.compose.AsyncImage

/** Android rendering of the existing NovelWebDetailView, not a new detail design.
 *  Measurements/structure follow STV/Novel/Legado/NovelSourceViews.swift.
 *  Source metadata is never replaced by an invented description or chapter list.
 */
@Composable
internal fun NovelBookDetail(
    book: NovelHit, info: NovelBookDetails?, sourceName: String, chapterCount: Int,
    loading: Boolean, error: String?, onShelf: Boolean, downloading: Boolean,
    downloadProgress: Float, onBack: () -> Unit, onSwitch: () -> Unit,
    onAdd: () -> Unit, onDownload: () -> Unit, onRead: () -> Unit, onRetry: () -> Unit
) {
    val c = IdjThemeColors
    val blue = Color(0xFF2868F0)
    val view=LocalView.current
    DisposableEffect(view,c.surface) {
        val activity=generateSequence(view.context){(it as? android.content.ContextWrapper)?.baseContext}.filterIsInstance<android.app.Activity>().firstOrNull()
        val window=activity?.window
        val old=window?.statusBarColor
        val controller=window?.let{WindowCompat.getInsetsController(it,view)}
        val oldLight=controller?.isAppearanceLightStatusBars
        if(window!=null){window.statusBarColor=c.surface.toArgb();controller?.isAppearanceLightStatusBars=c.surface.luminance()>.5f}
        onDispose {if(window!=null && old!=null){window.statusBarColor=old;if(oldLight!=null)controller?.isAppearanceLightStatusBars=oldLight}}
    }
    val title = info?.name?.takeIf { it.isNotBlank() } ?: book.name
    val author = info?.author?.takeIf { it.isNotBlank() } ?: book.author
    val cover = info?.cover?.takeIf { it.isNotBlank() } ?: book.cover
    val kind = (info?.kind?.takeIf { it.isNotBlank() } ?: book.kind).replace(Regex("[，,\\n]+"), " · ")
    val latest = info?.latest?.takeIf { it.isNotBlank() } ?: book.latest
    var sourceMenu by remember { mutableStateOf(false) }
    val enabled = (onShelf || !loading) && chapterCount > 0
    Column(Modifier.fillMaxSize().background(c.bg).testTag("novel.detail")) {
        Box(Modifier.fillMaxWidth().background(c.surface).statusBarsPadding().height(54.dp)) {
            IconButton(onClick=onBack,modifier=Modifier.align(Alignment.CenterStart).padding(start=8.dp)) {
                Icon(Icons.Outlined.ChevronLeft,"返回",tint=c.text,modifier=Modifier.size(30.dp))
            }
            Text(book.name,color=c.text,fontSize=17.sp,fontWeight=FontWeight.SemiBold,modifier=Modifier.align(Alignment.Center))
        }
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp),verticalArrangement=Arrangement.spacedBy(18.dp)) {
            Row(horizontalArrangement=Arrangement.spacedBy(16.dp),verticalAlignment=Alignment.Top) {
                Box(Modifier.size(100.dp,136.dp).clip(RoundedCornerShape(5.dp)).background(c.surface),contentAlignment=Alignment.Center) {
                    if(cover.isNotBlank()) AsyncImage(cover,book.name,Modifier.fillMaxSize(),contentScale=ContentScale.Crop)
                    else Text(book.name,color=c.secondary,fontSize=14.sp,modifier=Modifier.padding(10.dp))
                }
                Column(verticalArrangement=Arrangement.spacedBy(6.dp)) {
                    Text(title,color=c.text,fontSize=21.sp,fontWeight=FontWeight.Bold)
                    if(author.isNotBlank())Text(author,color=c.secondary,fontSize=17.sp)
                    if(kind.isNotBlank())Text(kind,color=c.secondary,fontSize=12.sp,maxLines=2)
                    if(chapterCount>0)Text("共 ${java.text.NumberFormat.getIntegerInstance().format(chapterCount)} 章",color=c.secondary,fontSize=12.sp)
                }
            }
            Box {
                Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(c.surface).clickable{sourceMenu=true}.height(45.dp).padding(horizontal=14.dp).testTag("novel.detail.source"),verticalAlignment=Alignment.CenterVertically) {
                Text("书源：$sourceName",color=blue,fontSize=14.sp,modifier=Modifier.weight(1f))
                Text("换源（1）",color=blue.copy(alpha=.55f),fontSize=14.sp)
                Spacer(Modifier.width(12.dp));Icon(Icons.Outlined.UnfoldMore,null,tint=blue,modifier=Modifier.size(18.dp))
            }
                DropdownMenu(sourceMenu,{sourceMenu=false}) {
                    DropdownMenuItem(text={Text(sourceName)},onClick={sourceMenu=false},trailingIcon={Icon(Icons.Outlined.Check,null)})
                    DropdownMenuItem(text={Text("搜索其他书源")},onClick={sourceMenu=false;onSwitch()})
                }
            }
            info?.intro?.trim()?.takeIf{it.isNotBlank()}?.let {
                Text(it,color=c.text,fontSize=15.sp,lineHeight=23.sp,modifier=Modifier.testTag("novel.detail.intro"))
            }
            if(latest.isNotBlank())Row(verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Outlined.Schedule,null,tint=c.secondary,modifier=Modifier.size(13.dp))
                Text("最新：$latest",color=c.secondary,fontSize=12.sp)
            }
            if(loading)Row(horizontalArrangement=Arrangement.spacedBy(8.dp),verticalAlignment=Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(18.dp),strokeWidth=2.dp,color=c.secondary)
                Text("正在读取目录…",color=c.secondary,fontSize=14.sp)
            }
            if(error!=null)Column(verticalArrangement=Arrangement.spacedBy(8.dp)) {
                Text(error,color=MaterialTheme.colorScheme.error,fontSize=14.sp)
                TextButton(onClick=onRetry){Text("重试",color=blue)}
            }
            if(downloading)LinearProgressIndicator(progress={downloadProgress},modifier=Modifier.fillMaxWidth(),color=blue)
        }
        Row(Modifier.fillMaxWidth().background(c.surface.copy(alpha=.97f)).navigationBarsPadding().padding(horizontal=20.dp,vertical=10.dp),horizontalArrangement=Arrangement.spacedBy(12.dp),verticalAlignment=Alignment.CenterVertically) {
            val pale=blue.copy(alpha=.15f)
            TextButton(onClick=onAdd,enabled=enabled&&!onShelf,modifier=Modifier.weight(1f).heightIn(min=58.dp).testTag("novel.detail.add"),colors=ButtonDefaults.textButtonColors(contentColor=blue,containerColor=pale)) {
                Text(if(onShelf)"已在书架" else "加入书架",fontSize=17.sp,maxLines=1)
            }
            TextButton(onClick=onDownload,enabled=enabled,contentPadding=PaddingValues(horizontal=12.dp),modifier=Modifier.heightIn(min=58.dp).testTag("novel.detail.download"),colors=ButtonDefaults.textButtonColors(contentColor=blue,containerColor=pale)) {
                Icon(Icons.Outlined.DownloadForOffline,null,Modifier.size(18.dp));Spacer(Modifier.width(5.dp));Text("下载",fontSize=17.sp)
            }
            Button(onClick=onRead,enabled=enabled,modifier=Modifier.weight(1f).heightIn(min=58.dp).testTag("novel.detail.read"),colors=ButtonDefaults.buttonColors(containerColor=blue,contentColor=Color.White),contentPadding=PaddingValues(horizontal=8.dp)) {
                Text("开始阅读",fontSize=17.sp,maxLines=1)
            }
        }
    }
}
