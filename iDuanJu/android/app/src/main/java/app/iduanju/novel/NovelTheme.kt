package app.iduanju.novel

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import app.iduanju.ui.theme.IdjThemeColors

@Composable
internal fun NovelPage(title: String, onBack: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    Dialog(onDismissRequest=onBack, properties=DialogProperties(usePlatformDefaultWidth=false)) {
        Surface(Modifier.fillMaxSize(), color=IdjThemeColors.bg) {
            Column(Modifier.fillMaxSize().systemBarsPadding()) {
                Row(Modifier.fillMaxWidth().background(IdjThemeColors.surface).heightIn(min=56.dp).padding(horizontal=8.dp), verticalAlignment=Alignment.CenterVertically) {
                    TextButton(onClick=onBack){Text("返回")}
                    Text(title,Modifier.weight(1f).padding(horizontal=8.dp),fontSize=17.sp,fontWeight=FontWeight.SemiBold,color=IdjThemeColors.text)
                }
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),verticalArrangement=Arrangement.spacedBy(20.dp),content=content)
            }
        }
    }
}

@Composable
internal fun NovelPanel(content: @Composable ColumnScope.() -> Unit) {
    Surface(Modifier.fillMaxWidth(),color=IdjThemeColors.surface,shape=RoundedCornerShape(14.dp)) {
        Column(Modifier.padding(16.dp),verticalArrangement=Arrangement.spacedBy(14.dp),content=content)
    }
}
