package app.iduanju

import androidx.compose.foundation.layout.fillMaxSize
import android.graphics.Bitmap
import android.util.Log
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import app.iduanju.ui.RootScreen
import app.iduanju.ui.theme.IdjTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.io.File

/** Live public home data: no fixture response or fabricated title/count is installed. */
class HomeHeroLayoutTest {
    @get:Rule val ui = createComposeRule()
    private fun verify(dark: Boolean) {
        val inst = InstrumentationRegistry.getInstrumentation()
        val ctx = inst.targetContext
        val density = ctx.resources.displayMetrics.density
        val config = ctx.resources.configuration
        val label = "${if(dark) "dark" else "light"}-${config.screenWidthDp}dp-f${config.fontScale}"
        ui.setContent { IdjTheme(dark = dark) { androidx.compose.material3.Surface(androidx.compose.ui.Modifier.fillMaxSize(), color = app.iduanju.ui.theme.IdjThemeColors.bg) { RootScreen() } } }
        ui.waitUntil(60000) { ui.onAllNodesWithTag("home.hero.pager").fetchSemanticsNodes().isNotEmpty() }
        ui.mainClock.autoAdvance = false
        fun node(tag: String) = ui.onNodeWithTag(tag, useUnmergedTree = true)
        fun bounds(tag: String): Rect = node(tag).fetchSemanticsNode().boundsInRoot
        fun inside(inner: Rect, outer: Rect) {
            assertTrue("$label: $inner must be inside $outer", inner.left >= outer.left - 1 && inner.top >= outer.top - 1 && inner.right <= outer.right + 1 && inner.bottom <= outer.bottom + 1)
        }
        var firstHeight: Float? = null
        for(i in 0..4) {
            node("home.hero.pager").performScrollToIndex(i)
            ui.mainClock.advanceTimeBy(700)
            ui.waitForIdle()
            node("home.hero.cta.$i").assertIsDisplayed()
            val page = bounds("home.hero.page.$i")
            val title = bounds("home.hero.title.$i")
            val cta = bounds("home.hero.cta.$i")
            val pill = bounds("home.hero.pill.$i")
            val text = bounds("home.hero.ctaText.$i")
            val dots = bounds("home.hero.dots.$i")
            assertTrue("CTA hit height must remain >=48dp: $cta", cta.height / density >= 47.9f)
            assertTrue("Visible white pill must remain >=32dp: $pill", pill.height / density >= 31.9f)
            inside(cta, page); inside(pill, cta); inside(text, pill); inside(dots, page)
            assertFalse("Dots cannot collide with CTA", dots.overlaps(cta))
            assertTrue("Title cannot crowd kicker", title.top >= bounds("home.hero.kicker.$i").bottom - 1)
            val metas = (0..1).mapNotNull { j -> runCatching { bounds("home.hero.meta.$i.$j") }.getOrNull() }
            var bottom = title.bottom
            metas.forEach { meta -> inside(meta, page); assertTrue("Metadata overlap", meta.top >= bottom - 1); bottom = meta.bottom }
            assertTrue("Metadata cannot crowd button", bottom + 6 * density <= cta.top + 1)
            val layouts = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            node("home.hero.ctaText.$i").performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            assertTrue("CTA text must have no overflow", layouts.isNotEmpty() && layouts.none { it.hasVisualOverflow })
            if(firstHeight == null) firstHeight = page.height else assertEquals("Pager height cannot jump with title length", firstHeight!!, page.height, 1f)
            val titleText = node("home.hero.title.$i").fetchSemanticsNode().config[androidx.compose.ui.semantics.SemanticsProperties.Text].joinToString { it.text }
            Log.i("IDJ_HOME_TEST", "$label page=$i title=$titleText page=$page titleRect=$title cta=$cta pill=$pill text=$text dots=$dots metadata=$metas")
            android.os.SystemClock.sleep(350)
            val bitmap = inst.uiAutomation.takeScreenshot()
            val file = File(ctx.getExternalFilesDir(null), "home-$label-page$i.png")
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }; bitmap.recycle()
        }
        ui.mainClock.autoAdvance = true
    }
    @Test fun lightRealHome() = verify(false)
    @Test fun darkRealHome() = verify(true)
}
