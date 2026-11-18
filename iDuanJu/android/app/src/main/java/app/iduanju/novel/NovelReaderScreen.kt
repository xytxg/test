package app.iduanju.novel

import android.app.Activity
import android.content.ContextWrapper
import android.speech.tts.TextToSpeech
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.*
import androidx.compose.foundation.gestures.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.shape.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.*
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.*
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.*
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.doOnLayout
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import app.iduanju.core.novel.NovelChapter
import coil.compose.AsyncImage
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.distinctUntilChanged
import org.json.JSONObject
import java.util.Locale
import kotlin.math.roundToInt

private val ReaderAccent=Color(0xFF309714)
private val turns=listOf("curl" to "仿真","slide" to "滑动","cover" to "覆盖","none" to "无动画","scroll" to "上下滚动")
private val fontNames=listOf("system" to "系统字体","songti" to "宋体","kaiti" to "楷体","yuanti" to "圆体","wenkai" to "霞鹜文楷","sourceserif" to "思源宋体","sourcesans" to "思源黑体")

/** Native peer of current iOS NovelReader. Reader canvas and menus are overlaid, never stacked. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun NovelReaderScreen(
    bookKey:String,bookTitle:String,author:String,cover:String,sourceName:String,
    chapters:List<NovelChapter>,chapterIndex:Int,body:String,busy:Boolean,error:String?,cached:Int,
    addedAt:Long=0,initialOffset:Int=0,onBack:()->Unit,onChapter:(Int)->Unit,onDownload:(Int)->Unit,onSwitch:(Int)->Unit,
    onLoadChapter:suspend(Int)->String,onSearch:suspend(String)->List<app.iduanju.core.novel.NovelCache.SearchHit>,onPrefetch:(Int)->Unit,onPosition:(Int,Int)->Unit
) {
    val context=LocalContext.current;val view=LocalView.current;val scope=rememberCoroutineScope()
    val prefs=remember{context.getSharedPreferences("novel",0)}
    var settings by remember{mutableStateOf(ReaderSettings.read(prefs.getString("reader.settings",null)))}
    val pal=ReaderPalette.of(settings.theme);val bg=Color(pal.bg);val panel=Color(pal.panel);val ink=Color(pal.ink);val secondary=Color(pal.secondary)
    var menu by remember(bookKey){mutableStateOf(false)};var tab by remember(bookKey){mutableStateOf("")}
    var endChapter by remember(bookKey){mutableIntStateOf(-1)};var page by remember{mutableIntStateOf(1)};var pages by remember{mutableIntStateOf(1)}
    var pageView by remember{mutableStateOf<NovelPageView?>(null)}
    var autoTurn by remember{mutableStateOf(false)};var brightness by remember{mutableFloatStateOf(.5f)}
    var listenError by remember{mutableStateOf<String?>(null)};var speech by remember{mutableStateOf<TextToSpeech?>(null)};var speaking by remember{mutableStateOf(false)};var rate by remember{mutableFloatStateOf(1f)}
    var fontBusy by remember{mutableStateOf<String?>(null)};var fontError by remember{mutableStateOf<String?>(null)};var fontRevision by remember{mutableIntStateOf(0)}
    var lastOffset by remember(bookKey){mutableIntStateOf(initialOffset)}
    var lastChapter by remember(bookKey){mutableIntStateOf(chapterIndex.coerceAtLeast(0))}
    val resume=remember(settings.turn){lastChapter to lastOffset}
    var scrollTarget by remember(bookKey,settings.turn){mutableStateOf(if(settings.turn=="scroll")resume else null)}
    val restoreScroll=scrollTarget!=null
    var jumpTarget by remember(bookKey){mutableStateOf<Pair<Int,Int>?>(null)}
    val scrollViews=remember(bookKey){mutableMapOf<Int,android.widget.TextView>()}
    val scrollState=rememberLazyListState(chapterIndex.coerceAtLeast(0))
    val texts=remember(bookKey){mutableStateMapOf<Int,String>()};val textErrors=remember(bookKey){mutableStateMapOf<Int,String>()}
    val current=if(settings.turn=="scroll")scrollState.firstVisibleItemIndex.coerceIn(0,(chapters.size-1).coerceAtLeast(0)) else chapterIndex.coerceAtLeast(0)
    val title=chapters.getOrNull(current)?.title.orEmpty()
    val activity=remember(view){generateSequence(view.context){(it as? ContextWrapper)?.baseContext}.filterIsInstance<Activity>().firstOrNull()}
    val density=LocalDensity.current
    val observedTop=maxOf(WindowInsets.statusBarsIgnoringVisibility.getTop(density),WindowInsets.displayCutout.getTop(density))
    val observedBottom=WindowInsets.navigationBars.getBottom(density)
    val stableTop=remember(bookKey){observedTop}
    val stableBottom=remember(bookKey){observedBottom}
    val readStart=remember(bookKey){android.os.SystemClock.elapsedRealtime()}
    val elapsedBefore=remember(bookKey){prefs.getLong("reader.time.$bookKey",0)}
    fun change(s:ReaderSettings){settings=s;prefs.edit().putString("reader.settings",s.json()).apply()}
    fun closeMenu(){menu=false;tab=""}
    fun jump(index:Int,offset:Int=0){
        if(index !in chapters.indices)return
        autoTurn=false
        if(settings.turn=="scroll"){scrollTarget=index to offset;scope.launch{scrollState.scrollToItem(index)}}
        else if(index==chapterIndex)pageView?.goToOffset(offset) else {endChapter=-1;jumpTarget=index to offset;onChapter(index)}
        closeMenu()
    }
    fun selectPanel(id:String){menu=true;tab=if(tab==id||(id=="font"&&tab in listOf("fonts","turn")))"" else id}
    DisposableEffect(activity,view){
        val w=activity?.window;val old=w?.attributes?.screenBrightness;val oldNav=w?.navigationBarColor
        val oldCutout=w?.attributes?.layoutInDisplayCutoutMode
        if(w!=null){WindowCompat.setDecorFitsSystemWindows(w,false);w.attributes=w.attributes.apply{layoutInDisplayCutoutMode=android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES}}
        onDispose{
            w?.let{WindowCompat.getInsetsController(it,view).show(WindowInsetsCompat.Type.statusBars());if(old!=null){it.attributes=it.attributes.apply{screenBrightness=old}};if(oldNav!=null)it.navigationBarColor=oldNav;if(oldCutout!=null)it.attributes=it.attributes.apply{layoutInDisplayCutoutMode=oldCutout}}
            prefs.edit().putLong("reader.time.$bookKey",elapsedBefore+android.os.SystemClock.elapsedRealtime()-readStart).apply()
        }
    }
    SideEffect {activity?.window?.let{w->val c=WindowCompat.getInsetsController(w,w.decorView);c.isAppearanceLightStatusBars=settings.theme!=3;c.isAppearanceLightNavigationBars=settings.theme!=3;w.statusBarColor=pal.bg;w.navigationBarColor=pal.bg;if(menu)c.show(WindowInsetsCompat.Type.statusBars()) else c.hide(WindowInsetsCompat.Type.statusBars())}}
    DisposableEffect(Unit){val t=TextToSpeech(context){status->if(status!=TextToSpeech.SUCCESS)listenError="朗读引擎不可用"};speech=t;onDispose{t.stop();t.shutdown()}}
    LaunchedEffect(body,chapterIndex){texts[chapterIndex.coerceAtLeast(0)]=body}
    LaunchedEffect(settings.turn){if(settings.turn=="scroll")scrollState.scrollToItem(resume.first) else if(resume.first!=chapterIndex)onChapter(resume.first)}
    LaunchedEffect(settings.turn,scrollState){var prefetched=-1;if(settings.turn=="scroll")snapshotFlow{Triple(scrollState.firstVisibleItemIndex,scrollState.firstVisibleItemScrollOffset,scrollTarget!=null)}.distinctUntilChanged().collect{(i,y,restoring)->
        if(!restoring){
            val t=scrollViews[i];val l=t?.layout
            val prefix=chapters.getOrNull(i)?.title?.takeIf{it.isNotBlank()}?.let{it.length+2}?:0
            val offset=if(l==null)0 else (l.getLineStart(l.getLineForVertical(y))-prefix).coerceAtLeast(0)
            lastChapter=i;lastOffset=offset;onPosition(i,offset);if(prefetched!=i){prefetched=i;onPrefetch(i)}
        }
    }}
    LaunchedEffect(autoTurn,settings.turn){if(autoTurn&&settings.turn!="scroll")while(isActive){delay(8000);pageView?.next()}}
    BackHandler{if(menu)closeMenu() else onBack()}
    Box(Modifier.fillMaxSize().background(bg).testTag("novel.reader")) {
        // Capture safe geometry once. System-bar visibility must not reflow or translate text.
        val contentPadding=with(density){PaddingValues(top=stableTop.toDp(),bottom=stableBottom.toDp())}
        if(settings.turn!="scroll")AndroidView(factory={NovelPageView(it).also{v->pageView=v}},modifier=Modifier.fillMaxSize().padding(contentPadding).testTag("novel.page").semantics{contentDescription=chapters.getOrNull(chapterIndex)?.title.orEmpty()+"\n"+body},update={v->
            v.onMenu={menu=!menu;if(!menu)tab=""};v.enabledTurns=!busy
            v.onEdge={d->val next=chapterIndex+d;if(next in chapters.indices){endChapter=if(d<0)next else -1;onChapter(next)}}
            v.onPosition={offset,p,n->lastChapter=chapterIndex.coerceAtLeast(0);lastOffset=offset;page=p;pages=n;onPosition(chapterIndex.coerceAtLeast(0),offset)}
            v.update(bookKey+"|"+chapterIndex+"|"+fontRevision,body,chapters.getOrNull(chapterIndex)?.title.orEmpty(),settings,if(jumpTarget?.first==chapterIndex)jumpTarget!!.second else if(endChapter==chapterIndex)Int.MAX_VALUE else if(lastChapter==chapterIndex)lastOffset else initialOffset)
            if(jumpTarget?.first==chapterIndex)jumpTarget=null
        }) else {
            Box(Modifier.fillMaxSize().padding(contentPadding)) {
                LazyColumn(state=scrollState,modifier=Modifier.fillMaxSize().testTag("novel.scroll").pointerInput(menu){detectTapGestures{p->if(p.x<size.width/3f)scope.launch{scrollState.animateScrollBy(-size.height*.85f)} else if(p.x>size.width*2/3f)scope.launch{scrollState.animateScrollBy(size.height*.85f)} else if(menu)closeMenu() else menu=true}},contentPadding=PaddingValues(start=(12+28*settings.margin).dp,end=(12+28*settings.margin).dp,top=32.dp,bottom=30.dp)) {
                    items(maxOf(1,chapters.size),key={chapters.getOrNull(it)?.url?:"local"}){i->
                        LaunchedEffect(bookKey,i){if(i !in texts)try{texts[i]=onLoadChapter(i)}catch(e:CancellationException){throw e}catch(e:Exception){textErrors[i]=e.message?:"章节读取失败"}}
                        AndroidView(factory={android.widget.TextView(it)},modifier=Modifier.fillMaxWidth().padding(bottom=24.dp),update={t->
                            scrollViews[i]=t
                            val content=texts[i]?:textErrors[i]?:"正文读取中…"
                            val identity=Triple(content,settings,fontRevision)
                            if(t.tag!=identity){
                                t.tag=identity;t.text=ReaderText.content(content,chapters.getOrNull(i)?.title.orEmpty(),settings,context.resources.displayMetrics.scaledDensity)
                                t.textSize=settings.font;t.typeface=ReaderText.typeface(context,settings.fontID);t.setTextColor(pal.ink);t.includeFontPadding=false;t.justificationMode=android.text.Layout.JUSTIFICATION_MODE_INTER_WORD
                                t.setLineSpacing(settings.font*context.resources.displayMetrics.scaledDensity*(.25f+.75f*settings.spacing),1f)
                            }
                            if(restoreScroll&&i==scrollTarget?.first&&i in texts)t.doOnLayout{
                                val l=t.layout?:return@doOnLayout
                                val prefix=chapters.getOrNull(i)?.title?.takeIf{it.isNotBlank()}?.let{it.length+2}?:0
                                val line=l.getLineForOffset(((scrollTarget?.second?:0)+prefix).coerceIn(0,t.text.length))
                                scope.launch{scrollState.scrollToItem(i,l.getLineTop(line));scrollTarget=null}
                            }
                        })
                    }
                }
                Text(title,color=secondary,fontSize=12.sp,modifier=Modifier.align(Alignment.TopStart).padding(horizontal=(12+28*settings.margin).dp))
                Text("${current+1}/${chapters.size}",color=secondary,fontSize=12.sp,modifier=Modifier.align(Alignment.BottomEnd).padding(horizontal=20.dp,vertical=8.dp))
            }
        }
        if(busy)CircularProgressIndicator(Modifier.align(Alignment.Center).size(24.dp),color=ReaderAccent,strokeWidth=2.dp)
        if(error!=null)Text(error,color=Color(0xFFB34747),fontSize=13.sp,modifier=Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top=56.dp).padding(horizontal=20.dp).background(panel,RoundedCornerShape(10.dp)).padding(12.dp))
        if(menu){
            Row(Modifier.align(Alignment.TopCenter).fillMaxWidth().background(bg.copy(alpha=.98f)).statusBarsPadding().height(44.dp).padding(horizontal=8.dp),verticalAlignment=Alignment.CenterVertically){
                IconButton(onClick=onBack,modifier=Modifier.testTag("novel.reader.back")){Icon(Icons.Outlined.ChevronLeft,"返回",tint=ink,modifier=Modifier.size(30.dp))};Spacer(Modifier.weight(1f))
                if(chapters.isNotEmpty()){TextButton(onClick={onSwitch(current)}){Text("换源",color=ink,fontSize=15.sp)};IconButton(onClick={onDownload(current)}){Icon(Icons.Outlined.DownloadForOffline,"下载",tint=ink)}}
            }
            Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth()) {
                Box(Modifier.fillMaxWidth().padding(end=16.dp,bottom=12.dp),contentAlignment=Alignment.CenterEnd){Text("听",fontSize=20.sp,color=Color.White,modifier=Modifier.size(48.dp).background(Color(0xE0333333),CircleShape).clickable{selectPanel("listen")}.wrapContentSize().testTag("novel.listen"))}
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(topStart=16.dp,topEnd=16.dp)).background(panel).navigationBarsPadding()){
                    if(tab.isNotEmpty())Column(Modifier.fillMaxWidth().padding(start=18.dp,end=18.dp,top=18.dp,bottom=6.dp),verticalArrangement=Arrangement.spacedBy(14.dp)) {
                        @Composable fun header(t:String){Row(verticalAlignment=Alignment.CenterVertically){IconButton(onClick={tab="font"},modifier=Modifier.size(32.dp).testTag("novel.panel.back")){Icon(Icons.Outlined.ChevronLeft,"返回设置",tint=ink,modifier=Modifier.size(20.dp))};Text(t,fontSize=15.sp,fontWeight=FontWeight.SemiBold,color=ink,modifier=Modifier.weight(1f))}}
                        @Composable fun pill(t:String,tag:String="",fill:Boolean=false,onClick:()->Unit){Box(Modifier.then(if(fill)Modifier.fillMaxWidth() else Modifier).clip(CircleShape).background(Color(pal.track).copy(alpha=.75f)).clickable(onClick=onClick).padding(horizontal=16.dp,vertical=11.dp).testTag(tag),contentAlignment=Alignment.Center){Text(t,color=ink,fontSize=14.sp,lineHeight=18.sp,fontWeight=FontWeight.Medium)}}
                        when(tab){
                            "font"->{
                                ReaderPillSlider((settings.font-12)/18,{change(settings.copy(font=(12+it*18).roundToInt().toFloat()))},settings,"${settings.font.toInt()}","A","A",Modifier.testTag("novel.font.size"))
                                Row(horizontalArrangement=Arrangement.spacedBy(14.dp)){ReaderPillSlider(settings.margin,{change(settings.copy(margin=it))},settings,"边距","","大",Modifier.weight(1f).testTag("novel.margin"));ReaderPillSlider(settings.spacing,{change(settings.copy(spacing=it))},settings,"行距","紧","松",Modifier.weight(1f).testTag("novel.spacing"))}
                                Row(Modifier.fillMaxWidth(),horizontalArrangement=Arrangement.spacedBy(12.dp)) {
                                    Box(Modifier.weight(1f)){pill((fontNames.firstOrNull{it.first==settings.fontID}?.second?:"字体样式")+" ›","novel.fonts",true){tab="fonts"}}
                                    Box(Modifier.weight(1f)){pill(if(settings.indent)"首行缩进 ›" else "不缩进 ›","novel.indent",true){change(settings.copy(indent=!settings.indent))}}
                                    Box(Modifier.weight(1f)){pill((turns.first{it.first==settings.turn}.second)+" ›","novel.turn",true){tab="turn"}}
                                }
                            }
                            "turn"->{
                                header("翻页方式")
                                turns.chunked(3).forEach{row->Row(horizontalArrangement=Arrangement.spacedBy(10.dp)){
                                    row.forEach{(id,name)->Box(Modifier.weight(1f).height(32.dp).clip(CircleShape).background(if(settings.turn==id)ReaderAccent.copy(alpha=.12f) else Color(pal.track).copy(alpha=.6f)).border(if(settings.turn==id)1.dp else 0.dp,if(settings.turn==id)ReaderAccent else Color.Transparent,CircleShape).clickable{autoTurn=false;change(settings.copy(turn=id))}.padding(horizontal=12.dp).testTag("novel.turn.$id"),contentAlignment=Alignment.Center){Text(name,color=if(settings.turn==id)ReaderAccent else ink,fontSize=13.sp,lineHeight=16.sp,fontWeight=if(settings.turn==id)FontWeight.SemiBold else FontWeight.Normal)}}
                                    repeat(3-row.size){Spacer(Modifier.weight(1f))}
                                }}
                                Text("仿真：像纸书一样卷页；滑动：两页并排滑过；覆盖：当前页盖在下一页上被拖走；上下滚动：整本书连续滚动。左右轻点也能翻页。",color=secondary,fontSize=11.sp,lineHeight=14.sp)
                            }
                            "light"->{ReaderPillSlider(brightness,{brightness=it;activity?.window?.let{w->w.attributes=w.attributes.apply{screenBrightness=brightness.coerceAtLeast(.01f)}}},settings,"","☀","",Modifier.testTag("novel.brightness"));Text("颜色",fontSize=12.sp,color=secondary);Row(horizontalArrangement=Arrangement.spacedBy(12.dp)){(0..3).forEach{i->Box(Modifier.weight(1f).height(40.dp).clip(RoundedCornerShape(10.dp)).background(Color(ReaderPalette.of(i).bg)).border(if(i==settings.theme)1.5.dp else .5.dp,if(i==settings.theme)ReaderAccent else Color.Gray.copy(alpha=.2f),RoundedCornerShape(10.dp)).clickable{change(settings.copy(theme=i))}.testTag("novel.theme.$i"),contentAlignment=Alignment.Center){if(i==3)Icon(Icons.Outlined.NightsStay,null,tint=Color(0xFF4D7CFE))}}}}
                            "toc"->ReaderTocPanel(chapters,current,lastOffset,(texts[current]?:body).length,pages,settings,::jump,onSearch)
                            "info"->ReaderInfoPanel(bookTitle,author,cover,chapters.size,sourceName,addedAt,elapsedBefore+android.os.SystemClock.elapsedRealtime()-readStart,settings)
                            "progress"->{
                                val fraction=if(chapters.isEmpty())0f else ((current*1000+lastOffset).toFloat()/(chapters.size*1000)).coerceIn(0f,1f)
                                ReaderProgressStats(fraction,current,chapters.size,elapsedBefore+android.os.SystemClock.elapsedRealtime()-readStart,settings)
                                Row(Modifier.fillMaxWidth().clip(CircleShape).background(Color(pal.track)),verticalAlignment=Alignment.CenterVertically){IconButton(onClick={jump(current-1)},enabled=current>0){Icon(Icons.Outlined.ChevronLeft,"上一章",tint=if(current>0)ink else secondary.copy(alpha=.4f))};ReaderPillSlider(fraction,{jump((it*chapters.size).toInt().coerceAtMost(chapters.lastIndex))},settings,"","","",Modifier.weight(1f).testTag("novel.progress.slider"),transparent=true);IconButton(onClick={jump(current+1)},enabled=current<chapters.lastIndex){Icon(Icons.Outlined.ChevronRight,"下一章",tint=ink)}}
                                Row(horizontalArrangement=Arrangement.spacedBy(14.dp)){
                                    Box(Modifier.weight(1f)){pill("回到本章开头",fill=true){jump(current)}}
                                    if(settings.turn!="scroll")Box(Modifier.weight(1f)){pill(if(autoTurn)"关闭自动翻页" else "开启自动翻页",fill=true){autoTurn=!autoTurn;if(autoTurn)closeMenu()}}
                                }
                            }
                            "fonts" -> {
                                header("字体样式")
                                fontError?.let{Text(it,color=Color.Red,fontSize=12.sp)}
                                Column(Modifier.heightIn(max=330.dp).verticalScroll(rememberScrollState())) {
                                    fontNames.forEach { (id,name) ->
                                        Row(Modifier.fillMaxWidth().clickable(enabled=fontBusy==null) {
                                            if(id in listOf("system","songti","kaiti","yuanti") || java.io.File(context.filesDir,"novel-fonts/$id.font").isFile) {
                                                change(settings.copy(fontID=id));fontRevision++
                                            } else {
                                                fontBusy=id;fontError=null
                                                scope.launch {
                                                    try {ReaderFontDownload.fetch(context,id);fontRevision++}
                                                    catch(e:CancellationException){throw e}
                                                    catch(e:Exception){fontError=e.message}
                                                    finally {fontBusy=null}
                                                }
                                            }
                                        }.padding(vertical=10.dp).testTag("novel.font.$id"),verticalAlignment=Alignment.CenterVertically) {
                                            Column(Modifier.weight(1f)) {
                                                Text(name,color=ink,fontSize=17.sp)
                                                Text(if(id in listOf("system","songti","kaiti","yuanti"))"系统字型 · 平台原生字体" else "SIL OFL 1.1 · 首次使用下载",fontSize=11.sp,color=secondary)
                                            }
                                            if(fontBusy==id)CircularProgressIndicator(Modifier.size(18.dp),color=ReaderAccent,strokeWidth=2.dp)
                                            else if(settings.fontID==id)Icon(Icons.Outlined.Check,null,tint=ReaderAccent)
                                            else if(id in listOf("wenkai","sourceserif","sourcesans") && !java.io.File(context.filesDir,"novel-fonts/$id.font").isFile)Text("下载",color=ReaderAccent,fontSize=12.sp)
                                        }
                                    }
                                }
                            }
                            "listen"->{header("听书");listenError?.let{Text(it,color=Color.Red,fontSize=12.sp)};ReaderPillSlider((rate-.5f)/1.5f,{rate=.5f+it*1.5f;speech?.setSpeechRate(rate)},settings,"语速","慢","快");Row(horizontalArrangement=Arrangement.spacedBy(12.dp)){pill(if(speaking)"暂停朗读" else "开始朗读"){val t=speech;if(speaking){t?.stop();speaking=false}else if(t!=null){val result=t.setLanguage(Locale.SIMPLIFIED_CHINESE);if(result<0)listenError="当前设备未安装中文语音，可在系统文字转语音设置中安装" else{t.setSpeechRate(rate);val value=texts[current]?:body;val chunks=value.chunked(TextToSpeech.getMaxSpeechInputLength());chunks.forEachIndexed{i,part->t.speak(part,if(i==0)TextToSpeech.QUEUE_FLUSH else TextToSpeech.QUEUE_ADD,null,"$bookKey:$current:$i")};speaking=true}}};pill("停止"){speech?.stop();speaking=false}}}
                        }
                    }
                    Row(Modifier.fillMaxWidth().height(56.dp),horizontalArrangement=Arrangement.SpaceAround,verticalAlignment=Alignment.CenterVertically){
                        listOf("toc" to Icons.Outlined.FormatListBulleted,"info" to Icons.Outlined.Explore,"progress" to Icons.Outlined.RadioButtonUnchecked,"light" to Icons.Outlined.WbSunny,"font" to Icons.Outlined.TextFields).forEach{(id,icon)->IconButton(onClick={selectPanel(id)},modifier=Modifier.testTag("novel.menu.$id")){if(id=="font")Text("A",fontSize=23.sp,fontWeight=FontWeight.Light,color=if(tab==id||tab in listOf("fonts","turn"))ReaderAccent else ink) else if(id=="progress")Canvas(Modifier.size(26.dp)){val color=if(tab==id)ReaderAccent else ink;drawCircle(color,size.minDimension*.32f,style=androidx.compose.ui.graphics.drawscope.Stroke(width=1.2.dp.toPx()));drawLine(color,androidx.compose.ui.geometry.Offset(0f,size.height/2),androidx.compose.ui.geometry.Offset(size.width,size.height/2),strokeWidth=1.2.dp.toPx())} else Icon(icon,when(id){"toc"->"目录";"info"->"书籍";"progress"->"进度";else->"亮度"},tint=if(tab==id)ReaderAccent else ink,modifier=Modifier.size(25.dp))}}
                    }
                }
            }
        }
    }
}

/** Pill track/label thumb matching existing iOS PillSlider, with accessible adjustable semantics. */
@Composable
private fun ReaderPillSlider(value:Float,onValue:(Float)->Unit,s:ReaderSettings,label:String="",leading:String="",trailing:String="",modifier:Modifier=Modifier,transparent:Boolean=false){
    val p=ReaderPalette.of(s.theme)
    val handle by rememberUpdatedState(onValue)
    BoxWithConstraints(modifier.fillMaxWidth().height(44.dp).clip(CircleShape).background(if(transparent)Color.Transparent else Color(p.track)).semantics{progressBarRangeInfo=ProgressBarRangeInfo(value,0f..1f);setProgress{onValue(it.coerceIn(0f,1f));true}}.pointerInput(Unit){
        detectDragGestures(onDragStart={handle((it.x/size.width).coerceIn(0f,1f))}){change,_->change.consume();handle((change.position.x/size.width).coerceIn(0f,1f))}
    }.pointerInput(Unit){detectTapGestures{handle((it.x/size.width).coerceIn(0f,1f))}}){
        Row(Modifier.fillMaxSize().padding(horizontal=16.dp),horizontalArrangement=Arrangement.SpaceBetween,verticalAlignment=Alignment.CenterVertically){Text(leading,color=Color(p.ink),fontSize=13.sp);Text(trailing,color=Color(p.ink),fontSize=15.sp)}
        Box(Modifier.offset(x=((maxWidth-44.dp)*value.coerceIn(0f,1f))).padding(2.dp).size(40.dp).shadow(3.dp,CircleShape).background(Color(p.thumb),CircleShape),contentAlignment=Alignment.Center){if(label.isNotEmpty())Text(label,color=Color(p.ink),fontSize=13.sp)}
    }
}
