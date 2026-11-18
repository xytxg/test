package app.iduanju.novel

import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.*
import androidx.compose.foundation.lazy.grid.*
import androidx.compose.foundation.shape.*
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.*
import androidx.compose.ui.draw.*
import androidx.compose.ui.graphics.*
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import app.iduanju.core.novel.*
import app.iduanju.ui.theme.IdjThemeColors
import app.iduanju.ui.components.*

/** Native redesign 04–08. Empty states never manufacture books or source results. */
@Composable
internal fun NovelShelf(books: List<Pair<String, NovelHit>>, hasLocal: Boolean, onBook: (String,NovelHit)->Unit,
    onLocal: ()->Unit, onImport: ()->Unit, onSearch: ()->Unit, onRank: ()->Unit, onSources: ()->Unit, embedded:Boolean=false) {
    val c=IdjThemeColors
    LazyColumn(contentPadding=PaddingValues(bottom=36.dp),verticalArrangement=Arrangement.spacedBy(20.dp)) {
        if(!embedded) {
            item { Row(Modifier.fillMaxWidth().padding(horizontal=16.dp),verticalAlignment=Alignment.CenterVertically) {
                Text("书架",color=c.text,fontSize=28.sp,fontWeight=FontWeight.ExtraBold,modifier=Modifier.weight(1f))
                RoundIconButton(Icons.Rounded.Add,"导入书籍",onClick=onImport)
            } }
            item { DSSearchBar("搜索书名、作者或书源",Modifier.padding(horizontal=16.dp).pressClick(onClick=onSearch)) }
        }
        if(hasLocal) item {
            Row(Modifier.padding(horizontal=16.dp).fillMaxWidth().dsCard().pressClick(onClick=onLocal).padding(16.dp),horizontalArrangement=Arrangement.spacedBy(16.dp)) {
                NovelPoster(NovelHit("本地小说","TXT 文件","local"),Modifier.size(72.dp,100.dp))
                Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                    Text("本地小说",color=c.text,fontSize=18.sp,fontWeight=FontWeight.Bold)
                    Text("离线阅读 · 已导入",color=c.secondary,fontSize=13.sp)
                    Spacer(Modifier.height(8.dp)); CapsuleButton("继续阅读",Icons.Rounded.PlayArrow,onClick=onLocal)
                }
            }
        }
        if(books.isNotEmpty()) item {
            val (src,b)=books.first()
            Row(Modifier.padding(horizontal=16.dp).fillMaxWidth().dsCard().pressClick {onBook(src,b)}.padding(16.dp),horizontalArrangement=Arrangement.spacedBy(16.dp)) {
                NovelPoster(b,Modifier.size(72.dp,100.dp))
                Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(8.dp)) {
                    Text("继续阅读",color=c.accentWarm,fontSize=12.sp,fontWeight=FontWeight.SemiBold)
                    Text(b.name,color=c.text,fontSize=20.sp,fontWeight=FontWeight.Bold,maxLines=1)
                    Text(b.author,color=c.secondary,fontSize=13.sp)
                    DSStatus("已缓存 · 可离线阅读",StatusTone.Ok)
                    CapsuleButton("继续阅读",Icons.Rounded.PlayArrow){onBook(src,b)}
                }
            }
        }
        item { Row(Modifier.fillMaxWidth().padding(horizontal=16.dp),horizontalArrangement=Arrangement.spacedBy(10.dp)) {
            ShelfQuick(Icons.Rounded.Search,"搜书",Modifier.weight(1f),onSearch)
            ShelfQuick(Icons.Rounded.Leaderboard,"排行榜",Modifier.weight(1f),onRank)
            ShelfQuick(Icons.Rounded.Cloud,"书源",Modifier.weight(1f),onSources)
            ShelfQuick(Icons.Rounded.FileDownload,"导入",Modifier.weight(1f),onImport)
        } }
        item { SectionHeader2("我的书架","${books.size+if(hasLocal)1 else 0} 本",trailing={MoreLink("导入",onClick=onImport)}) }
        if(books.isEmpty()&&!hasLocal) item { EmptyNovel("书架空空的","导入本地 TXT，或添加书源后搜索并缓存喜欢的小说。") }
        items(books.chunked(3)) { row -> Row(Modifier.fillMaxWidth().padding(horizontal=16.dp),horizontalArrangement=Arrangement.spacedBy(16.dp)) {
            row.forEach { (src,b)->Column(Modifier.weight(1f).pressClick {onBook(src,b)},verticalArrangement=Arrangement.spacedBy(8.dp)) {
                NovelPoster(b,Modifier.fillMaxWidth().aspectRatio(0.7f));Text(b.name,color=c.text,fontSize=14.sp,fontWeight=FontWeight.SemiBold,maxLines=1,overflow=TextOverflow.Ellipsis)
                Text(b.author,color=c.secondary,fontSize=11.sp,maxLines=1)
            } }; repeat(3-row.size){Spacer(Modifier.weight(1f))}
        } }
    }
}
@Composable private fun ShelfQuick(icon: androidx.compose.ui.graphics.vector.ImageVector,label:String,modifier:Modifier,onClick:()->Unit){
    val c=IdjThemeColors
    Column(modifier.dsCard(16.dp).pressClick(onClick=onClick).padding(vertical=14.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(8.dp)) {
        Icon(icon,null,tint=c.accent,modifier=Modifier.size(23.dp));Text(label,color=c.text,fontSize=12.sp,fontWeight=FontWeight.Medium)
    }
}
@Composable internal fun NovelPoster(book:NovelHit,modifier:Modifier){
    val c=IdjThemeColors
    Box(modifier.shadow(5.dp,RoundedCornerShape(8.dp)).clip(RoundedCornerShape(8.dp)).background(Brush.linearGradient(listOf(c.accentSoft,c.elevated))),contentAlignment=Alignment.Center){
        if(book.cover.isNotBlank())coil.compose.AsyncImage(book.cover,null,Modifier.matchParentSize(),contentScale=ContentScale.Crop)
        else Text(book.name.take(12),color=c.text,fontSize=15.sp,fontWeight=FontWeight.Bold,modifier=Modifier.padding(12.dp))
        Box(Modifier.fillMaxHeight().width(6.dp).align(Alignment.CenterStart).background(Brush.horizontalGradient(listOf(Color.Black.copy(0.18f),Color.Transparent))))
    }
}
@Composable internal fun EmptyNovel(title:String,note:String){val c=IdjThemeColors
    Column(Modifier.fillMaxWidth().padding(28.dp),horizontalAlignment=Alignment.CenterHorizontally,verticalArrangement=Arrangement.spacedBy(12.dp)){
        Icon(Icons.Rounded.MenuBook,null,tint=c.tertiary,modifier=Modifier.size(38.dp));Text(title,color=c.text,fontSize=17.sp,fontWeight=FontWeight.SemiBold)
        Text(note,color=c.secondary,fontSize=13.sp,lineHeight=20.sp,textAlign=androidx.compose.ui.text.style.TextAlign.Center)
    }
}
@Composable internal fun NovelSearchField(value:String,onValue:(String)->Unit,onSubmit:()->Unit){val c=IdjThemeColors
    Row(Modifier.padding(horizontal=16.dp).fillMaxWidth().height(46.dp).clip(CircleShape).background(c.glass).border(1.dp,c.glassBorder,CircleShape).padding(horizontal=16.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)){
        Icon(Icons.Rounded.Search,null,tint=c.secondary,modifier=Modifier.size(20.dp))
        BasicTextField(value,onValue,Modifier.weight(1f),singleLine=true,textStyle=TextStyle(color=c.text,fontSize=16.sp),cursorBrush=SolidColor(c.accent),
            keyboardOptions=KeyboardOptions(imeAction=ImeAction.Search),keyboardActions=KeyboardActions(onSearch={onSubmit()}),decorationBox={inner->Box{if(value.isEmpty())Text("书名 / 作者",color=c.tertiary,fontSize=16.sp);inner()}})
        if(value.isNotEmpty())Icon(Icons.Rounded.Cancel,"清除",tint=c.tertiary,modifier=Modifier.size(18.dp).clickable{onValue("")})
    }
}
@Composable internal fun NovelResult(book:NovelHit,rank:Int?,sourceName:String,onClick:()->Unit){val c=IdjThemeColors
    Row(Modifier.fillMaxWidth().pressClick(0.985f,onClick=onClick).padding(horizontal=16.dp,vertical=13.dp),horizontalArrangement=Arrangement.spacedBy(12.dp)){
        if(rank!=null) RankNumeral(rank,18,Modifier.width(20.dp).padding(top=26.dp))
        NovelPoster(book,Modifier.size(if(rank==null)58.dp else 54.dp,if(rank==null)81.dp else 75.dp))
        Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(6.dp)){
            Text(book.name,color=c.text,fontSize=16.sp,fontWeight=FontWeight.Bold,maxLines=1,overflow=TextOverflow.Ellipsis)
            Text(listOf(book.author,book.kind).filter{it.isNotBlank()}.joinToString(" · "),color=c.secondary,fontSize=12.sp,maxLines=1)
            if(book.latest.isNotBlank())Text("最新：${book.latest}",color=c.tertiary,fontSize=11.sp,maxLines=1)
            if(rank==null)Row(horizontalArrangement=Arrangement.spacedBy(6.dp)){DSStatus("1 个书源",StatusTone.Accent);DSTag(sourceName)}
        }
    }
}
@Composable internal fun NovelSourcesPage(sources:List<NovelSource>,onBack:()->Unit,onAdd:()->Unit,onToggle:(NovelSource,Boolean)->Unit,onDelete:(NovelSource)->Unit){val c=IdjThemeColors
    var filter by remember{mutableStateOf("全部")}
    Column(Modifier.fillMaxSize().background(c.bg).statusBarsPadding()){
        DSNavBar("书源",leading={BackButton(onClick=onBack)},trailing={RoundIconButton(Icons.Rounded.Add,"导入书源",Tone.Accent,onClick=onAdd)})
        Text("共 ${sources.size} 个书源 · 已启用 ${sources.count{it.enabled}} 个",color=c.secondary,fontSize=13.sp,modifier=Modifier.padding(horizontal=20.dp,vertical=16.dp))
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal=16.dp),horizontalArrangement=Arrangement.spacedBy(8.dp)){
            listOf("全部","已启用","需登录").forEach{f->ToneChip(f,f==filter,count=when(f){"已启用"->sources.count{it.enabled};"需登录"->sources.count{it.json.optString("loginUrl").isNotBlank()};else->sources.size}){filter=f}}
        }
        LazyColumn(Modifier.padding(top=16.dp).fillMaxWidth(),contentPadding=PaddingValues(horizontal=16.dp,vertical=4.dp)){
            if(sources.isEmpty())item{EmptyNovel("还没有书源","添加 Legado 文本书源，即可搜索与浏览榜单。")}
            items(sources.filter{when(filter){"已启用"->it.enabled;"需登录"->it.json.optString("loginUrl").isNotBlank();else->true}},key={it.id}){s->
                var menu by remember{mutableStateOf(false)}
                Row(Modifier.fillMaxWidth().background(c.surface).padding(horizontal=14.dp,vertical=14.dp),verticalAlignment=Alignment.CenterVertically,horizontalArrangement=Arrangement.spacedBy(10.dp)){
                    IconWell(Icons.Rounded.Cloud)
                    Column(Modifier.weight(1f),verticalArrangement=Arrangement.spacedBy(6.dp)){
                        Text(s.name,color=c.text,fontSize=15.sp,fontWeight=FontWeight.SemiBold,maxLines=1)
                        Text(runCatching{java.net.URI(s.id).host}.getOrNull().orEmpty(),color=c.tertiary,fontSize=11.sp,maxLines=1)
                        if(s.json.optString("loginUrl").isNotBlank())DSStatus("需登录",StatusTone.Warn)
                    }
                    Switch(s.enabled,{onToggle(s,it)},colors=SwitchDefaults.colors(checkedThumbColor=c.onAccent,checkedTrackColor=c.accent))
                    Box{Icon(Icons.Rounded.MoreVert,"更多",Modifier.size(24.dp).clickable{menu=true},tint=c.secondary)
                        DropdownMenu(menu,{menu=false}){DropdownMenuItem(text={Text("删除书源")},onClick={menu=false;onDelete(s)})}}
                };Hairline()
            }
        }
    }
}
