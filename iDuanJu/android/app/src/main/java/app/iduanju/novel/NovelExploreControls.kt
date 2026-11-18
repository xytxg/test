package app.iduanju.novel

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import app.iduanju.core.novel.NovelCategory
import kotlinx.coroutines.delay

/** Source-defined controls are not URL categories. Flex width/wrap is honored outside the narrow rail. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun NovelExploreControls(controls:List<NovelCategory>,enabled:Boolean,onAction:(NovelCategory,String?)->Unit) {
    if(controls.isEmpty())return
    BoxWithConstraints(Modifier.fillMaxWidth().heightIn(max=240.dp).verticalScroll(rememberScrollState()).padding(horizontal=12.dp)) {
        val width=maxWidth
        FlowRow(horizontalArrangement=Arrangement.spacedBy(6.dp),verticalArrangement=Arrangement.spacedBy(2.dp)) {
            controls.forEach { c ->
                if(c.style.wrapBefore)Spacer(Modifier.fillMaxWidth().height(0.dp))
                val child=if(c.style.basis>0)Modifier.width((width*c.style.basis.coerceAtMost(1.0).toFloat()).coerceAtLeast(48.dp)) else if(c.style.grow>0)Modifier.weight(c.style.grow.toFloat()) else Modifier
                Box(child.testTag("novel.filter."+c.title)) {
                    when(c.type) {
                        "text" -> {
                            var text by remember(c.selectionKey,c.value){mutableStateOf(c.value)}
                            val action by rememberUpdatedState(onAction)
                            LaunchedEffect(text,enabled){if(enabled&&text!=c.value){delay(450);action(c,text)}}
                            OutlinedTextField(value=text,onValueChange={text=it},label={Text(c.displayTitle)},singleLine=true,enabled=enabled,modifier=Modifier.widthIn(min=140.dp))
                        }
                        "select" -> {
                            var open by remember{mutableStateOf(false)}
                            TextButton(enabled=enabled,onClick={open=true}){Text(c.displayTitle+"："+c.value+" ▾")}
                            DropdownMenu(expanded=open,onDismissRequest={open=false}){c.chars.forEach { value -> DropdownMenuItem(text={Text(value)},onClick={open=false;onAction(c,value)}) }}
                        }
                        "toggle" -> FilterChip(selected=c.chars.indexOf(c.value)>0,enabled=enabled,onClick={onAction(c,null)},label={Text(c.value+c.displayTitle)})
                        else -> TextButton(enabled=enabled,onClick={onAction(c,null)}){Text(c.displayTitle)}
                    }
                }
            }
        }
    }
}
