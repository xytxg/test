package app.iduanju.ui

/** Debug-only native-simulator evidence hooks, populated only in a Debug build's MainActivity. */
object UiEvidence {
    var keepChrome = false
    var page: String = ""
    var panel: String? = null
    var scroll = false
    var landscape = false
    var switchEpisode = false
}
