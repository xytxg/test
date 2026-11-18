package app.iduanju.novel

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.text.*
import android.text.style.*
import android.view.MotionEvent
import android.view.View
import org.json.JSONObject
import kotlin.math.*

internal data class ReaderSettings(
    val font:Float=18f,val spacing:Float=.5f,val margin:Float=.3f,val indent:Boolean=true,
    val theme:Int=0,val turn:String="slide",val fontID:String="system"
) {
    fun json()=JSONObject().put("font",font.toDouble()).put("spacing",spacing.toDouble()).put("margin",margin.toDouble()).put("indent",indent).put("theme",theme).put("turn",turn).put("fontID",fontID).toString()
    companion object {fun read(raw:String?):ReaderSettings=runCatching{val j=JSONObject(raw?:"{}");ReaderSettings(j.optDouble("font",18.0).toFloat().coerceIn(12f,30f),j.optDouble("spacing",.5).toFloat().coerceIn(0f,1f),j.optDouble("margin",.3).toFloat().coerceIn(0f,1f),j.optBoolean("indent",true),j.optInt("theme",0).coerceIn(0,3),j.optString("turn","slide"),j.optString("fontID","system"))}.getOrDefault(ReaderSettings())}
}
internal data class ReaderPalette(val bg:Int,val panel:Int,val track:Int,val thumb:Int,val ink:Int,val secondary:Int) {
    companion object {fun of(theme:Int)=when(theme){
        1->ReaderPalette(0xFFF7F0DE.toInt(),0xFFF1E8D0.toInt(),0xFFE6DABE.toInt(),0xFFFBF6EA.toInt(),0xFF1F1F1F.toInt(),0xFF8F8F8F.toInt())
        2->ReaderPalette(0xFFBFEDC4.toInt(),0xFFB8EDBD.toInt(),0xFFA9D9AF.toInt(),0xFFCCEFCF.toInt(),0xFF1F1F1F.toInt(),0xFF6D886F.toInt())
        3->ReaderPalette(0xFF111111.toInt(),0xFF1C1C1C.toInt(),0xFF2B2B2B.toInt(),0xFF4A4A4A.toInt(),0xFF949494.toInt(),0xFF777777.toInt())
        else->ReaderPalette(Color.WHITE,0xFFF6F6F6.toInt(),0xFFE6E6E6.toInt(),Color.WHITE,0xFF1F1F1F.toInt(),0xFF8F8F8F.toInt())
    }}
}

/** Same text metrics as iOS NovelLayout. Body offsets exclude the chapter heading. */
internal object ReaderText {
    fun typeface(context:Context,id:String):Typeface {
        val file=java.io.File(context.filesDir,"novel-fonts/$id.font")
        if(file.isFile)return runCatching{Typeface.createFromFile(file)}.getOrDefault(Typeface.DEFAULT)
        return Typeface.create(if(id=="songti")"serif" else if(id=="kaiti")"cursive" else if(id=="yuanti")"sans-serif-rounded" else "sans-serif",Typeface.NORMAL)
    }
    fun content(body:String,title:String,s:ReaderSettings,scale:Float):SpannableString {
        val prefix=if(title.isBlank())"" else title+"\n\n"
        val clean=body.lines().map{it.trim()}.filter{it.isNotBlank()}.joinToString("\n")
        val text=SpannableString(prefix+clean)
        if(title.isNotBlank()){
            text.setSpan(RelativeSizeSpan(1.3f),0,title.length,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            text.setSpan(StyleSpan(Typeface.BOLD),0,title.length,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
        var start=prefix.length
        for(line in clean.split('\n')){
            val end=min(text.length,start+line.length+1)
            if(end>start){
                if(s.indent)text.setSpan(LeadingMarginSpan.Standard((s.font*scale*2).roundToInt(),0),start,end,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                val last=end
                text.setSpan(object:LineHeightSpan {override fun chooseHeight(t:CharSequence,a:Int,b:Int,v:Int,ht:Int,fm:Paint.FontMetricsInt){if(b>=last)fm.descent+=(s.font*scale*(.25f+.75f*s.spacing)*.35f).roundToInt()}},start,end,Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
            start=end
        }
        return text
    }
}

/** Native StaticLayout paginator; chrome is a sibling overlay and can never resize its viewport. */
internal class NovelPageView(context:Context):View(context) {
    init {isClickable=true;isFocusable=true;importantForAccessibility=IMPORTANT_FOR_ACCESSIBILITY_YES}
    var onMenu:()->Unit={};var onEdge:(Int)->Unit={};var onPosition:(Int,Int,Int)->Unit={_,_,_->}
    var enabledTurns=true
    private var settings=ReaderSettings();private var body="";private var chapter="";private var key=""
    private var layout:StaticLayout?=null;private var firstLines=listOf(0);private var page=0;private var pendingOffset=0
    private val ink=TextPaint(Paint.ANTI_ALIAS_FLAG);private val small=Paint(Paint.ANTI_ALIAS_FLAG);private val fill=Paint(Paint.ANTI_ALIAS_FLAG)
    private val density=resources.displayMetrics.density;private val scale=resources.displayMetrics.scaledDensity
    private var drag=0f;private var downX=0f;private var downY=0f;private var moved=false;private var animator:ValueAnimator?=null
    private val margin get()=(12+28*settings.margin)*density
    private val bodyHeight get()=(height-62*density).coerceAtLeast(1f)
    private val palette get()=ReaderPalette.of(settings.theme)
    fun update(newKey:String,text:String,title:String,s:ReaderSettings,offset:Int){
        if(key==newKey && body==text && chapter==title && settings==s)return
        val same=key==newKey;val preserve=if(same)currentOffset() else offset
        animator?.cancel();key=newKey;body=text;chapter=title;settings=s;pendingOffset=preserve;drag=0f;rebuild()
    }
    fun currentOffset():Int {val l=layout?:return pendingOffset;return (l.getLineStart(firstLines.getOrElse(page){0})-(if(chapter.isBlank())0 else chapter.length+2)).coerceAtLeast(0)}
    fun goToOffset(offset:Int){pendingOffset=offset;rebuild()}
    fun firstPage(){page=0;drag=0f;notifyPosition();invalidate()}
    fun next(direction:Int=1){if(!enabledTurns||animator?.isRunning==true)return;val target=page+direction;if(target !in firstLines.indices){onEdge(direction);return};animateTurn(direction,0f)}
    override fun onSizeChanged(w:Int,h:Int,ow:Int,oh:Int){pendingOffset=currentOffset();rebuild()}
    private fun rebuild(){
        if(width<=0||height<=0)return
        ink.textSize=settings.font*scale;ink.typeface=ReaderText.typeface(context,settings.fontID);ink.color=palette.ink
        val text=ReaderText.content(body,chapter,settings,scale)
        val l=StaticLayout.Builder.obtain(text,0,text.length,ink,(width-2*margin).roundToInt().coerceAtLeast(1))
            .setIncludePad(false).setAlignment(Layout.Alignment.ALIGN_NORMAL).setLineSpacing(settings.font*scale*(.25f+.75f*settings.spacing),1f)
            .setBreakStrategy(Layout.BREAK_STRATEGY_HIGH_QUALITY).setHyphenationFrequency(Layout.HYPHENATION_FREQUENCY_NONE)
            .setJustificationMode(Layout.JUSTIFICATION_MODE_INTER_WORD).build()
        layout=l;val starts=mutableListOf(0);var line=0
        while(line<l.lineCount){var end=line+1;while(end<l.lineCount && l.getLineBottom(end)-l.getLineTop(line)<=bodyHeight)end++;line=end;if(line<l.lineCount)starts+=line}
        firstLines=starts
        val wanted=if(pendingOffset==Int.MAX_VALUE)text.length else pendingOffset+(if(chapter.isBlank())0 else chapter.length+2)
        page=starts.indexOfLast{l.getLineStart(it)<=wanted}.coerceAtLeast(0)
        notifyPosition();invalidate()
    }
    private fun notifyPosition(){onPosition(currentOffset(),page+1,firstLines.size)}
    private fun drawPage(c:Canvas,index:Int,dx:Float=0f){
        if(index !in firstLines.indices)return
        val save=c.save();c.translate(dx,0f);fill.color=palette.bg;c.drawRect(0f,0f,width.toFloat(),height.toFloat(),fill)
        small.textSize=12*scale;small.color=palette.secondary;small.typeface=Typeface.DEFAULT
        val header=TextUtils.ellipsize(chapter,TextPaint(small),(width-2*margin),TextUtils.TruncateAt.END).toString()
        c.drawText(header,margin,15*density,small)
        val l=layout
        if(l!=null){val bodySave=c.save();c.clipRect(margin,32*density,width-margin,32*density+bodyHeight)
            c.translate(margin,32*density-l.getLineTop(firstLines[index]));l.draw(c);c.restoreToCount(bodySave)}
        val footer="${index+1}/${firstLines.size}";c.drawText(footer,width-margin-small.measureText(footer),height-10*density,small);c.restoreToCount(save)
    }
    override fun onDraw(c:Canvas){
        super.onDraw(c)
        if(abs(drag)<.1f){drawPage(c,page);return}
        val direction=if(drag<0)1 else -1;val target=page+direction
        if(target !in firstLines.indices){drawPage(c,page,drag*.15f);return}
        when(settings.turn){
            "cover"->{drawPage(c,target);drawPage(c,page,drag);fill.shader=LinearGradient(if(drag<0)width+drag else drag,0f,if(drag<0)width+drag+18*density else drag-18*density,0f,0x44000000,Color.TRANSPARENT,Shader.TileMode.CLAMP);c.drawRect(0f,0f,width.toFloat(),height.toFloat(),fill);fill.shader=null}
            "curl"->{
                drawPage(c,target);val progress=(abs(drag)/width).coerceIn(0f,1f);val edge=if(direction>0)width*(1-progress) else width*progress
                val fold=sin(progress*Math.PI).toFloat()*min(64*density,width*.2f)
                val path=Path();if(direction>0){path.moveTo(0f,0f);path.lineTo(edge,0f);path.quadTo(edge-fold,height*.5f,edge,height.toFloat());path.lineTo(0f,height.toFloat())}
                else{path.moveTo(width.toFloat(),0f);path.lineTo(edge,0f);path.quadTo(edge+fold,height*.5f,edge,height.toFloat());path.lineTo(width.toFloat(),height.toFloat())};path.close()
                val save=c.save();c.clipPath(path);drawPage(c,page);c.restoreToCount(save)
                val band=Path().apply{moveTo(edge,0f);quadTo(edge-direction*fold,height*.5f,edge,height.toFloat());quadTo(edge+direction*fold*.65f,height*.5f,edge,0f);close()}
                fill.shader=LinearGradient(edge-fold,0f,edge+fold.coerceAtLeast(1f),0f,intArrayOf(0x33000000,palette.panel,0x66000000),null,Shader.TileMode.CLAMP);c.drawPath(band,fill);fill.shader=null
            }
            else->{drawPage(c,target,drag+direction*width);drawPage(c,page,drag)}
        }
    }
    private fun animateTurn(direction:Int,from:Float){
        if(settings.turn=="none"){page+=direction;drag=0f;notifyPosition();invalidate();return}
        animator=ValueAnimator.ofFloat(from,-direction*width.toFloat()).apply{duration=220
            addUpdateListener{drag=it.animatedValue as Float;invalidate()}
            addListener(object:android.animation.AnimatorListenerAdapter(){private var cancelled=false;override fun onAnimationCancel(a:android.animation.Animator){cancelled=true};override fun onAnimationEnd(a:android.animation.Animator){if(!cancelled){page=(page+direction).coerceIn(firstLines.indices);drag=0f;notifyPosition();invalidate()}}});start()}
    }
    override fun onTouchEvent(e:MotionEvent):Boolean{
        if(e.actionMasked==MotionEvent.ACTION_DOWN){downX=e.x;downY=e.y;moved=false;animator?.cancel()}
        if(e.actionMasked==MotionEvent.ACTION_MOVE){val dx=e.x-downX;val dy=e.y-downY;if(abs(dx)>12*density||abs(dy)>12*density)moved=true
            if(moved&&abs(dx)>abs(dy)&&enabledTurns){drag=dx.coerceIn(-width.toFloat(),width.toFloat());invalidate()}}
        if(e.actionMasked==MotionEvent.ACTION_UP && !moved){when{e.x<width/3f->next(-1);e.x>width*2/3f->next(1);else->performClick()}}
        if(e.actionMasked==MotionEvent.ACTION_UP && moved){val dx=e.x-downX;val dy=e.y-downY
            if(abs(dy)>abs(dx)&&dy< -40*density){drag=0f;onMenu();invalidate()}
            else if(abs(dx)>width*.15f && enabledTurns){val dir=if(dx<0)1 else -1;if(page+dir in firstLines.indices)animateTurn(dir,drag) else{drag=0f;onEdge(dir);invalidate()}}
            else{drag=0f;invalidate()}}
        if(e.actionMasked==MotionEvent.ACTION_CANCEL){drag=0f;invalidate()};return true
    }
    override fun performClick():Boolean{onMenu();return super.performClick()}
    override fun onDetachedFromWindow(){animator?.cancel();super.onDetachedFromWindow()}
}
