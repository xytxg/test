package app.iduanju.novel

import android.content.Context
import android.graphics.Typeface
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.util.concurrent.TimeUnit

/** Same optional SIL-OFL fonts/versions as iOS NovelFonts. Apple's proprietary fonts are never copied. */
internal object ReaderFontDownload {
    private data class Font(val root:String,val path:String,val license:String)
    private val fonts=mapOf(
        "wenkai" to Font("lxgw/LxgwWenKai-Lite/v1.530","fonts/TTF/LXGWWenKaiLite-Regular.ttf","OFL.txt"),
        "sourceserif" to Font("adobe-fonts/source-han-serif/2.003R","SubsetOTF/CN/SourceHanSerifCN-Regular.otf","LICENSE.txt"),
        "sourcesans" to Font("adobe-fonts/source-han-sans/2.005R","SubsetOTF/CN/SourceHanSansCN-Regular.otf","LICENSE.txt")
    )
    private val http=OkHttpClient.Builder().callTimeout(120,TimeUnit.SECONDS).build()
    suspend fun fetch(context:Context,id:String)=withContext(Dispatchers.IO){
        val font=fonts[id]?:error("未知字体");val dir=File(context.filesDir,"novel-fonts").apply{mkdirs()}
        val base="https://raw.githubusercontent.com/${font.root}/"
        fun bytes(path:String,max:Int):ByteArray=http.newCall(Request.Builder().url(base+path).build()).execute().use{r->
            check(r.isSuccessful){"字体下载失败：HTTP ${r.code}"};val out=java.io.ByteArrayOutputStream()
            r.body!!.byteStream().use{input->val buffer=ByteArray(16384);while(true){val n=input.read(buffer);if(n<0)break;check(out.size()+n<=max){"字体文件过大"};out.write(buffer,0,n)}};out.toByteArray()
        }
        val license=bytes(font.license,200000).toString(Charsets.UTF_8)
        check(license.contains("SIL OPEN FONT LICENSE",ignoreCase=true)){"字体授权信息不完整，未安装"}
        currentCoroutineContext().ensureActive()
        File(dir,"$id-LICENSE.txt").writeText(license)
        val tmp=File(dir,"$id.part")
        try{tmp.writeBytes(bytes(font.path,24*1024*1024));currentCoroutineContext().ensureActive();Typeface.createFromFile(tmp)
            java.nio.file.Files.move(tmp.toPath(),File(dir,"$id.font").toPath(),java.nio.file.StandardCopyOption.REPLACE_EXISTING)
        }finally{tmp.delete()}
    }
}
