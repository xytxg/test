package app.iduanju.core.novel

/** Original implementation of the neighbor-first policy documented in Legado-E
 * ReadBook.kt (GPL-3.0), revision 8b87c5aba4df91c39a3a0939a68a1180b9f2ee1c.
 * See docs/novel-android-ios-parity-20261117.md. No upstream implementation copied.
 */
object NovelPrefetchPlan {
    fun indices(current: Int, size: Int, count: Int): List<Int> {
        if(current !in 0 until size || count <= 0) return emptyList()
        val forward=count.coerceAtMost(20)
        return (listOf(current+1,current-1) + (2..forward).map{current+it} +
            (2..minOf(5,forward)).map{current-it}).filter{it in 0 until size}.distinct()
    }
}
