package app.iduanju.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBackIos
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.iduanju.ui.theme.IdjThemeColors
import coil.compose.AsyncImage
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.HazeStyle
import dev.chrisbanes.haze.hazeEffect

// i短剧 redesign building blocks — Compose twin of iOS DesignKit.swift. Every size is the spec's pt value as dp.

object DS {
    /** Selection (tabs / segments / chips) and panel springs; same feel as the iOS springs. */
    fun <T> select() = spring<T>(dampingRatio = 0.86f, stiffness = 380f)
    fun <T> panel() = spring<T>(dampingRatio = 0.88f, stiffness = 230f)
    fun <T> press() = spring<T>(dampingRatio = 0.8f, stiffness = Spring.StiffnessMedium)

    /** "512.6 万", "1.2 亿". */
    fun count(n: Long): String = when {
        n >= 100_000_000 -> String.format("%.1f 亿", n / 100_000_000.0)
        n >= 10_000 -> String.format("%.1f 万", n / 10_000.0)
        else -> n.toString()
    }

    /** "更新至24集" → "更新至 24 集". */
    fun spaced(t: String): String {
        val out = StringBuilder(); var prev: Boolean? = null
        for (ch in t) {
            val d = ch.isDigit() || ch == '.'
            if (prev != null && prev != d && ch != ' ' && out.lastOrNull() != ' ') out.append(' ')
            out.append(ch); prev = if (ch == ' ') null else d
        }
        return out.toString()
    }
}

// MARK: surfaces

/** `.card`: fill + 1 dp border; light mode adds the soft shadow. */
@Composable
fun Modifier.dsCard(radius: Dp = 20.dp): Modifier {
    val c = IdjThemeColors; val s = RoundedCornerShape(radius)
    return this
        .then(if (!c.dark) Modifier.shadow(14.dp, s, ambientColor = c.shadowSoft, spotColor = Color.Black.copy(0.10f)) else Modifier)
        .clip(s).background(c.card).border(1.dp, c.cardBorder, s)
}

/** Floating glass bar (tab bar, sticky strip, play bar). Real blur on API 31+ through Haze. */
@Composable
fun Modifier.dsBar(radius: Dp, haze: HazeState? = null): Modifier {
    val c = IdjThemeColors; val s = RoundedCornerShape(radius)
    val blur = haze != null && android.os.Build.VERSION.SDK_INT >= 31
    return this
        .shadow(20.dp, s, ambientColor = c.barShadow, spotColor = c.barShadow)
        .clip(s)
        .then(if (blur) Modifier.hazeEffect(haze!!, HazeStyle(c.bar, emptyList(), 22.dp, noiseFactor = 0f)) else Modifier.background(c.sheet.copy(alpha = 0.94f)))
        .background(if (blur) Color.Transparent else c.bar)
        .border(1.dp, c.glassBorder, s)
}

/** Pinned header: page colour 80 % over blur + bottom hairline; fades in with [on]. */
@Composable
fun Modifier.dsPinned(on: Boolean, haze: HazeState? = null): Modifier {
    val c = IdjThemeColors
    val a by animateFloatAsState(if (on) 1f else 0f, label = "pin")
    val blur = haze != null && android.os.Build.VERSION.SDK_INT >= 31 && on
    return this
        .then(if (blur) Modifier.hazeEffect(haze!!, HazeStyle(c.pin, emptyList(), 20.dp, noiseFactor = 0f)) else Modifier)
        .drawWithContent {
            drawRect(if (blur) Color.Transparent else c.bg.copy(alpha = 0.96f * a))
            drawRect(c.pin.copy(alpha = c.pin.alpha * a))
            drawRect(c.hairline.copy(alpha = c.hairline.alpha * a), topLeft = Offset(0f, size.height - 1.dp.toPx()), size = androidx.compose.ui.geometry.Size(size.width, 1.dp.toPx()))
            drawContent()
        }
}

/** radial-gradient(130% 100% at 25% -8%, c0 0, c1 36–40 %, transparent 72 %) over the top 380 dp. */
@Composable
fun AmbientGlow(cool: Boolean = false, visible: Boolean = true, modifier: Modifier = Modifier) {
    val c = IdjThemeColors
    val cs = if (cool) c.ambientCool else c.ambientWarm
    val a by animateFloatAsState(if (visible) 1f else 0f, label = "amb")
    Box(modifier.fillMaxWidth().height(380.dp).graphicsLayer { alpha = a }.drawWithContent {
        val r = size.width * 1.3f
        drawRect(Brush.radialGradient(0f to cs[0], (if (cool) 0.40f else 0.36f) to cs[1], 0.72f to cs[1].copy(alpha = 0f),
            center = Offset(size.width * 0.25f, -size.height * 0.08f), radius = r))
    })
}

/** Page ground + top glow. */
@Composable
fun DSPage(cool: Boolean = false, glow: Boolean = true, modifier: Modifier = Modifier, content: @Composable BoxScope.() -> Unit) {
    Box(modifier.fillMaxSize().background(IdjThemeColors.bg)) {
        AmbientGlow(cool, glow)
        content()
    }
}

@Composable
fun Hairline(modifier: Modifier = Modifier) = Box(modifier.fillMaxWidth().height(1.dp).background(IdjThemeColors.hairline))

/** Press feedback (spec "按下"): scale 0.96 and 85 % opacity. */
fun Modifier.pressClick(scale: Float = 0.96f, enabled: Boolean = true, label: String? = null, onClick: () -> Unit): Modifier = composed {
    val src = remember { MutableInteractionSource() }
    val pressed by src.collectIsPressedAsState()
    val s by animateFloatAsState(if (pressed) scale else 1f, DS.press(), label = "press")
    this.graphicsLayer { scaleX = s; scaleY = s; alpha = if (pressed) 0.85f else 1f }
        .clickable(src, null, enabled = enabled, onClick = onClick)
        .then(if (label != null) Modifier.semantics { contentDescription = label } else Modifier)
}

// MARK: level 1 — underline tabs (`.ttabs`)

@Composable
fun <T> UnderlineTabs(items: List<T>, selected: T, label: (T) -> String, small: Boolean = false, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    val c = IdjThemeColors
    val d = LocalDensity.current
    val pos = remember { mutableStateMapOf<Int, Pair<Float, Float>>() }
    val idx = items.indexOf(selected).coerceAtLeast(0)
    val target = pos[idx]
    val uw = if (small) 22.dp else 26.dp
    val x by animateDpAsState(with(d) { target?.let { (l, w) -> if (small) (l + (w - uw.toPx()) / 2).toDp() else (l + 1.dp.toPx()).toDp() } ?: 0.dp }, DS.select(), label = "ux")
    Box(modifier.height(if (small) 34.dp else 40.dp)) {
        Row(Modifier.align(if (small) Alignment.CenterStart else Alignment.BottomStart), horizontalArrangement = Arrangement.spacedBy(if (small) 24.dp else 22.dp), verticalAlignment = Alignment.Bottom) {
            items.forEachIndexed { i, it ->
                val on = i == idx
                Text(label(it),
                    color = if (on) c.text else c.secondary,
                    fontSize = if (on) (if (small) 18.sp else 24.sp) else (if (small) 16.sp else 17.sp),
                    fontWeight = if (on) (if (small) FontWeight.Bold else FontWeight.ExtraBold) else FontWeight.Normal,
                    maxLines = 1,
                    modifier = Modifier.onGloballyPositioned { pos[i] = it.positionInParent().x to it.size.width.toFloat() }
                        .padding(bottom = if (small) 0.dp else 6.dp)
                        .clickable(remember { MutableInteractionSource() }, null) { onSelect(it) }
                        .semantics { contentDescription = "tabs.${label(it)}" })
            }
        }
        if (target != null) Box(Modifier.align(Alignment.BottomStart).offset(x = x, y = if (small) 0.dp else 0.dp)
            .size(uw, if (small) 3.dp else 4.dp).clip(CircleShape).background(c.accent))
    }
}

// MARK: level 2 — segmented control (`.seg`): 40 dp, radius 14, padding 3, thumb radius 11

@Composable
fun <T> SegmentedTabs(items: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    val c = IdjThemeColors
    val idx = items.indexOf(selected).coerceAtLeast(0)
    BoxWithConstraints(modifier.fillMaxWidth().height(40.dp).clip(RoundedCornerShape(14.dp)).background(c.glass).border(1.dp, c.hairline, RoundedCornerShape(14.dp)).padding(3.dp)) {
        val w = maxWidth / items.size.coerceAtLeast(1)
        val x by animateDpAsState(w * idx, DS.select(), label = "seg")
        Box(Modifier.offset(x = x).width(w).fillMaxHeight()
            .then(if (!c.dark) Modifier.shadow(3.dp, RoundedCornerShape(11.dp), ambientColor = c.shadowThumb, spotColor = c.shadowThumb) else Modifier)
            .clip(RoundedCornerShape(11.dp)).background(c.thumb))
        Row(Modifier.fillMaxSize()) {
            items.forEachIndexed { i, it ->
                val on = i == idx
                val col by animateColorAsState(if (on) c.text else c.secondary, label = "segc")
                Box(Modifier.weight(1f).fillMaxHeight().clickable(remember { MutableInteractionSource() }, null) { onSelect(it) }
                    .semantics { contentDescription = "seg.${label(it)}" }, contentAlignment = Alignment.Center) {
                    Text(label(it), color = col, fontSize = 14.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium, maxLines = 1)
                }
            }
        }
    }
}

// MARK: level 3 — tone chips (`.chip`): 32 dp, padding 14, font 14

@Composable
fun ToneChip(title: String, on: Boolean, neutral: Boolean = false, small: Boolean = false, count: Int? = null, enabled: Boolean = true, onClick: () -> Unit) {
    val c = IdjThemeColors
    val fill by animateColorAsState(if (on) (if (neutral) c.thumb else c.accentSoft) else c.glass, label = "chip")
    val ink by animateColorAsState(if (on) (if (neutral) c.text else c.accent) else c.secondary, label = "chipInk")
    Row(Modifier
        .graphicsLayer { alpha = if (enabled) 1f else 0.38f }
        .then(if (on && neutral && !c.dark) Modifier.shadow(3.dp, CircleShape, ambientColor = c.shadowThumb, spotColor = c.shadowThumb) else Modifier)
        .clip(CircleShape).background(fill)
        .then(if (on && !neutral) Modifier.border(1.dp, c.accentLine, CircleShape) else Modifier)
        .pressClick(0.97f, enabled, onClick = onClick)
        .height(if (small) 28.dp else 32.dp).padding(horizontal = if (small) 12.dp else 14.dp)
        .semantics { contentDescription = "chip.$title" },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(title, color = ink, fontSize = if (small) 13.sp else 14.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal, maxLines = 1)
        if (count != null) Text("$count", color = ink.copy(alpha = ink.alpha * 0.72f), fontSize = 12.sp, fontWeight = FontWeight.Medium)
    }
}

/** One scrolling chip row; right edge fades (`.chips.fade`). */
@Composable
fun <T> ChipRow(items: List<T>, selected: T, label: (T) -> String, onSelect: (T) -> Unit, neutral: (T) -> Boolean = { false },
                small: Boolean = false, fade: Boolean = true, start: Dp = 16.dp, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth().then(if (fade) Modifier.fadeEnd() else Modifier).horizontalScroll(rememberScrollState())
        .padding(start = start, end = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        items.forEach { ToneChip(label(it), it == selected, neutral(it), small) { onSelect(it) } }
    }
}

fun Modifier.fadeEnd(from: Float = 0.84f): Modifier = this.graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }.drawWithContent {
    drawContent()
    drawRect(Brush.horizontalGradient(from to Color.Black, 1f to Color.Transparent), blendMode = BlendMode.DstIn)
}

// MARK: buttons

enum class Tone { Glass, Accent, Overlay }

/** `.cbtn`: 36 dp round button. */
@Composable
fun RoundIconButton(icon: ImageVector, label: String, tone: Tone = Tone.Glass, size: Dp = 36.dp, onClick: () -> Unit) {
    val c = IdjThemeColors
    val bg = when (tone) { Tone.Accent -> c.accentSoft; Tone.Overlay -> Color.Black.copy(0.30f); Tone.Glass -> c.glass }
    val fg = when (tone) { Tone.Accent -> c.accent; Tone.Overlay -> Color.White; Tone.Glass -> c.text }
    val br = when (tone) { Tone.Accent -> Color.Transparent; Tone.Overlay -> Color.White.copy(0.16f); Tone.Glass -> c.hairline }
    Box(Modifier.size(size).clip(CircleShape).background(bg).border(1.dp, br, CircleShape).pressClick(label = label, onClick = onClick),
        contentAlignment = Alignment.Center) { Icon(icon, null, Modifier.size(18.dp), tint = fg) }
}

@Composable
fun BackButton(tone: Tone = Tone.Glass, onClick: () -> Unit) =
    RoundIconButton(Icons.AutoMirrored.Rounded.ArrowBackIos, "返回", tone) { onClick() }

/** `.capbtn`: 36 dp capsule. */
@Composable
fun CapsuleButton(title: String, icon: ImageVector? = null, trailing: ImageVector? = null, onClick: () -> Unit) {
    val c = IdjThemeColors
    Row(Modifier.height(36.dp).clip(CircleShape).background(c.glass).border(1.dp, c.hairline, CircleShape).pressClick(label = title, onClick = onClick)
        .padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (icon != null) Icon(icon, null, Modifier.size(16.dp), tint = c.secondary)
        Text(title, color = c.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 200.dp))
        if (trailing != null) Icon(trailing, null, Modifier.size(14.dp), tint = c.secondary)
    }
}

enum class PillTone { Accent, Ink, White }

/** `.btn`: 48 dp accent / ink / white capsule (32 dp small). */
@Composable
fun PillButton(title: String, modifier: Modifier = Modifier, icon: ImageVector? = null, tone: PillTone = PillTone.Accent, small: Boolean = false,
               height: Dp? = null, enabled: Boolean = true, onClick: () -> Unit) {
    val c = IdjThemeColors
    val bg = when (tone) { PillTone.Accent -> c.accent; PillTone.Ink -> c.text; PillTone.White -> Color.White }
    val fg = when (tone) { PillTone.Accent -> c.onAccent; PillTone.Ink -> c.bg; PillTone.White -> Color(0xFF111317) }
    Row(modifier.height(height ?: if (small) 32.dp else 48.dp).clip(CircleShape).background(bg).pressClick(0.98f, enabled, title, onClick)
        .padding(horizontal = if (small) 14.dp else 22.dp), verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally)) {
        if (icon != null) Icon(icon, null, Modifier.size(if (small) 14.dp else 18.dp), tint = fg)
        Text(title, color = fg, fontSize = if (small) 13.sp else 16.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

/** `.mini`: small accent capsule action. */
@Composable
fun MiniButton(title: String, onClick: () -> Unit) {
    val c = IdjThemeColors
    Box(Modifier.height(30.dp).clip(CircleShape).background(c.accentSoft).pressClick(label = title, onClick = onClick).padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center) { Text(title, color = c.accent, fontSize = 13.sp, fontWeight = FontWeight.SemiBold) }
}

// MARK: nav / search / headers

/** `.nav`: 44 dp bar, 96 dp side slots, centred 17 sp title. */
@Composable
fun DSNavBar(title: String, modifier: Modifier = Modifier, titleAlpha: Float = 1f, leading: @Composable () -> Unit = {}, trailing: @Composable () -> Unit = {}) {
    Row(modifier.fillMaxWidth().height(44.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.width(96.dp), contentAlignment = Alignment.CenterStart) { leading() }
        Text(title, Modifier.weight(1f).graphicsLayer { alpha = titleAlpha }, color = IdjThemeColors.text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
            maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        Box(Modifier.width(96.dp), contentAlignment = Alignment.CenterEnd) { trailing() }
    }
}

/** `.search`: 46 dp glass capsule (placeholder only; the real field lives in the search screens). */
@Composable
fun DSSearchBar(placeholder: String = "搜索你想看的作品", modifier: Modifier = Modifier, ink: Color? = null, trailing: @Composable RowScope.() -> Unit = {}) {
    val c = IdjThemeColors
    Row(modifier.fillMaxWidth().height(46.dp).clip(CircleShape).background(c.glass).border(1.dp, c.glassBorder, CircleShape).padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Rounded.Search, null, Modifier.size(20.dp), tint = ink ?: c.secondary)
        Text(placeholder, Modifier.weight(1f), color = ink ?: c.secondary, fontSize = 16.sp, maxLines = 1)
        trailing()
    }
}

/** `.sech`: 19 sp bold title + note + trailing. */
@Composable
fun SectionHeader2(title: String, note: String? = null, inset: Dp = 16.dp, modifier: Modifier = Modifier, trailing: @Composable () -> Unit = {}) {
    val c = IdjThemeColors
    Row(modifier.fillMaxWidth().padding(horizontal = inset), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, color = c.text, fontSize = 19.sp, fontWeight = FontWeight.Bold)
        if (note != null) Text(note, color = c.secondary, fontSize = 13.sp, modifier = Modifier.padding(bottom = 2.dp))
        Spacer(Modifier.weight(1f))
        trailing()
    }
}

/** "全部 ›" (`.more`). */
@Composable
fun MoreLink(title: String = "全部", icon: ImageVector? = null, onClick: () -> Unit) {
    val c = IdjThemeColors
    Row(Modifier.pressClick(label = title, onClick = onClick), verticalAlignment = Alignment.CenterVertically) {
        if (icon != null) Icon(icon, null, Modifier.size(14.dp).padding(end = 3.dp), tint = c.secondary)
        Text(title, color = c.secondary, fontSize = 13.sp)
        if (icon == null) Icon(Icons.Rounded.ChevronRight, null, Modifier.size(14.dp), tint = c.secondary)
    }
}

/** `.tag`: neutral 20 dp label. */
@Composable
fun DSTag(text: String) {
    val c = IdjThemeColors
    Box(Modifier.height(20.dp).clip(RoundedCornerShape(6.dp)).background(c.glass).padding(horizontal = 7.dp), contentAlignment = Alignment.Center) {
        Text(text, color = c.secondary, fontSize = 11.sp, maxLines = 1)
    }
}

enum class StatusTone { Ok, Warn, Muted, Accent }

/** `.st`: status label. */
@Composable
fun DSStatus(text: String, tone: StatusTone) {
    val c = IdjThemeColors
    val (fg, bg) = when (tone) {
        StatusTone.Ok -> c.ok to c.okSoft; StatusTone.Warn -> c.accentWarm to c.warmSoft
        StatusTone.Muted -> c.tertiary to c.glass; StatusTone.Accent -> c.accent to c.accentSoft
    }
    Box(Modifier.height(20.dp).clip(RoundedCornerShape(6.dp)).background(bg).padding(horizontal = 7.dp), contentAlignment = Alignment.Center) {
        Text(text, color = fg, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

/** `.bar`: 3 dp progress track. */
@Composable
fun DSProgressBar(value: Float, modifier: Modifier = Modifier) {
    val c = IdjThemeColors
    val v by animateFloatAsState(value.coerceIn(0f, 1f), label = "bar")
    Box(modifier.fillMaxWidth().height(3.dp).clip(CircleShape).background(c.glassBorder)) {
        Box(Modifier.fillMaxHeight().fillMaxWidth(v).clip(CircleShape).background(c.accent))
    }
}

/** `.dot` / `.lico`: tinted icon well. */
@Composable
fun IconWell(icon: ImageVector, size: Dp = 34.dp, corner: Dp? = null) {
    val c = IdjThemeColors
    Box(Modifier.size(size).clip(RoundedCornerShape(corner ?: (size / 2))).background(c.accentSoft), contentAlignment = Alignment.Center) {
        Icon(icon, null, Modifier.size(size * 0.5f), tint = c.accent)
    }
}

// MARK: posters

/** Rank numeral on posters: italic 800, gold / silver / bronze for the top 3. */
@Composable
fun RankNumeral(rank: Int, size: Int = 20, modifier: Modifier = Modifier) {
    val c = IdjThemeColors
    Text("$rank", modifier, color = c.rankColor(rank), fontSize = size.sp, fontWeight = FontWeight.ExtraBold, fontStyle = FontStyle.Italic, maxLines = 1)
}

/** Poster with bottom scrim and optional top-left rank numeral (`.poster`). */
@Composable
fun PosterArt(url: String, modifier: Modifier = Modifier, corner: Dp = 12.dp, rank: Int? = null, badge: String? = null) {
    val c = IdjThemeColors
    Box(modifier.clip(RoundedCornerShape(corner)).background(c.glass)) {
        AsyncImage(url, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(0.46f to Color.Transparent, 1f to Color.Black.copy(0.62f))))
        if (rank != null) {
            Text("$rank", Modifier.align(Alignment.TopStart).padding(start = 8.dp, top = 4.dp), color = when (rank) {
                1 -> Color(0xFFFFC740); 2 -> Color(0xFFADBAD6); 3 -> Color(0xFFDB8C52); else -> Color.White
            }, fontSize = 30.sp, fontWeight = FontWeight.ExtraBold, fontStyle = FontStyle.Italic,
                style = androidx.compose.ui.text.TextStyle(shadow = androidx.compose.ui.graphics.Shadow(Color.Black.copy(0.4f), Offset(0f, 2f), 6f)))
        }
        if (!badge.isNullOrEmpty()) Text(badge, Modifier.align(Alignment.BottomStart).padding(8.dp), color = Color.White.copy(0.9f), fontSize = 11.sp, fontWeight = FontWeight.Medium)
    }
}
