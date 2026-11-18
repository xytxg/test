package app.iduanju.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * Pixel-matched to iOS STVTheme (Theme.swift). The second block are the ui-redesign tokens
 * (ui-redesign/styles.css); screens use these instead of ad-hoc colours.
 */
data class IdjColors(
    val dark: Boolean,
    val bg: Color,
    val surface: Color,
    val elevated: Color,
    val text: Color,
    val secondary: Color,
    val accent: Color,
    val accentWarm: Color,
    val tertiary: Color,
    val glass: Color,
    val glassBorder: Color,
    val hairline: Color,
    val accentSoft: Color,
    val accentLine: Color,
    val onAccent: Color,
    val warmSoft: Color,
    val ok: Color,
    val okSoft: Color,
    val card: Color,
    val cardBorder: Color,
    val thumb: Color,
    val bar: Color,
    val sheet: Color,
    val rail: Color,
    val gold: Color,
    val silver: Color,
    val bronze: Color,
    val pin: Color,
    val dim: Color,
    val shadowSoft: Color,
    val shadowThumb: Color,
    val barShadow: Color,
    val ambientWarm: List<Color>,
    val ambientCool: List<Color>,
) {
    fun rankColor(r: Int): Color = when (r) { 1 -> gold; 2 -> silver; 3 -> bronze; else -> tertiary }
}

private val Dark = IdjColors(
    dark = true,
    bg = Color(0xFF111317), // 0.067,0.075,0.090
    surface = Color(0xFF1C1F25), // 0.110,0.122,0.145
    elevated = Color(0xFF393D42), // 0.224,0.239,0.259
    text = Color(0xFFEEF0F3), // 0.933,0.941,0.953
    secondary = Color(0xFFADB5BF), // 0.68,0.71,0.75
    accent = Color(0xFF8AB4FF), // 0.541,0.706,1
    accentWarm = Color(0xFFF2B55C), // 0.949,0.710,0.361
    tertiary = Color(0x9EADB5BF),
    glass = Color(0x12EEF0F3),
    glassBorder = Color(0x1FEEF0F3),
    hairline = Color(0x14EEF0F3),
    accentSoft = Color(0x298AB4FF),
    accentLine = Color(0x6B8AB4FF),
    onAccent = Color(0xFF0D1B36),
    warmSoft = Color(0x26F2B55C),
    ok = Color(0xFF5FD08A),
    okSoft = Color(0x245FD08A),
    card = Color(0x0EEEF0F3),
    cardBorder = Color(0x1AEEF0F3),
    thumb = Color(0x29EEF0F3),
    bar = Color(0xB8181B21),
    sheet = Color(0xFF1C1F25),
    rail = Color(0x09EEF0F3),
    gold = Color(0xFFFFC740),
    silver = Color(0xFFC7D1E6),
    bronze = Color(0xFFDB8C52),
    pin = Color(0xCC111317),
    dim = Color(0x85000000),
    shadowSoft = Color(0x00000000),
    shadowThumb = Color(0x00000000),
    barShadow = Color(0x4C000000),
    ambientWarm = listOf(Color(0x94965C3E), Color(0x4C603C32)),
    ambientCool = listOf(Color(0x574868A8), Color(0x2928385C)),
)

private val Light = IdjColors(
    dark = false,
    bg = Color(0xFFF4F5F7), // 0.957,0.961,0.969
    surface = Color(0xFFFFFFFF),
    elevated = Color(0xFFE8EAEE), // 0.910,0.918,0.933
    text = Color(0xFF121418), // 0.071,0.078,0.094
    secondary = Color(0xFF5F6672), // 0.373,0.400,0.447
    accent = Color(0xFF286DEF), // 0.157,0.427,0.937
    accentWarm = Color(0xFFD58514), // 0.835,0.522,0.078
    tertiary = Color(0xAD5F6672),
    glass = Color(0x0E121418),
    glassBorder = Color(0x1A121418),
    hairline = Color(0x12121418),
    accentSoft = Color(0x1A286DEF),
    accentLine = Color(0x5C286DEF),
    onAccent = Color(0xFFFFFFFF),
    warmSoft = Color(0x1FD58514),
    ok = Color(0xFF1E9E57),
    okSoft = Color(0x1F1E9E57),
    card = Color(0xFFFFFFFF),
    cardBorder = Color(0x0F121418),
    thumb = Color(0xFFFFFFFF),
    bar = Color(0xCCFFFFFF),
    sheet = Color(0xFFFFFFFF),
    rail = Color(0x09121418),
    gold = Color(0xFFDB9A00),
    silver = Color(0xFF8793AD),
    bronze = Color(0xFFC5733A),
    pin = Color(0xCCF4F5F7),
    dim = Color(0x57121418),
    shadowSoft = Color(0x0F121418),
    shadowThumb = Color(0x1A121418),
    barShadow = Color(0x1F121418),
    ambientWarm = listOf(Color(0x2BD58514), Color(0x0FD58514)),
    ambientCool = listOf(Color(0x26286DEF), Color(0x0D286DEF)),
)

val LocalIdjColors = staticCompositionLocalOf { Dark }

/** The player, image viewer and readers stay dark: wrap them in `IdjTheme(dark = true)`. */
@Composable
fun IdjTheme(dark: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    val colors = if (dark) Dark else Light
    val scheme = if (dark) darkColorScheme(
        primary = colors.accent, onPrimary = colors.onAccent, background = colors.bg,
        surface = colors.surface, onBackground = colors.text, onSurface = colors.text,
        secondary = colors.secondary,
    ) else lightColorScheme(
        primary = colors.accent, onPrimary = colors.onAccent, background = colors.bg,
        surface = colors.surface, onBackground = colors.text, onSurface = colors.text,
        secondary = colors.secondary,
    )
    CompositionLocalProvider(LocalIdjColors provides colors) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

val IdjThemeColors: IdjColors
    @Composable get() = LocalIdjColors.current

/** The player always renders on black with the dark palette (spec `.pl`), whatever the app theme is. */
val IdjDarkColors: IdjColors get() = Dark
