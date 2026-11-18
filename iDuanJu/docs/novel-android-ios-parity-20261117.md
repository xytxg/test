# Android novel parity milestone — 2026-11-17 (PST)

## Scope / publication gate

The current iOS detail and reader are the reference, not rollback targets. **No production iOS appearance or reader code is changed.** This milestone implements the Android **detail** portion and bounded Android preload/cache corrections. Android **reader appearance/controls are still not at iOS parity**; its screenshot is deliberately named `reader-still-pending`. No merge/push/release is authorized. Do not describe this milestone as complete reader parity.

Worktree: `/Users/edy/Code/Iduanju-rank`; branch `codex/novel-reader-restore`, based on fetched `origin/main` `eaf4a500cc9b103949bbdc538940c39668ac24d7`. Existing integrated ranking fix `11bdef1` (original local `d974e33`) is preserved. Own iOS simulator `E258CA6F-4207-4AB4-A893-40F9F58F9A20`; Android `emulator-5556` / `iduanju_rank`. Neither other worktrees nor other workers' simulators were used.

## History / actual cause

- `git diff v1.5b10-novel..eaf4a50 -- STV/Novel/NovelReader.swift STV/Novel/NovelPager.swift STV/Novel/NovelTheme.swift` is empty. The claim that b11 restyled the iOS reader was incorrect.
- `git blame eaf4a50` identifies `5eaf47c5` as the origin of permanent A−/A+ controls and raw reader LazyColumn; `b7d3abd2` added the permanent cache/source row and raw detail cache/TOC controls.
- Android `NovelScreen.kt` used a title/TOC-only detail and permanently visible reader toolbar instead of the existing iOS detail/reader implementation. This was a missing Android parity implementation, not a reason to revert good iOS UI.
- `b5d6c8d86e1d8e05b09876d7529c3ecf094d00b2` (Android 04–08 restyle) removed the surrounding 16dp padding and used the rank/search DSNavBar for detail/reader too, making the mismatch more conspicuous. `7199100` additionally changed embedding/status-bar behavior. Historical module rollback would not recreate iOS parity.

## Implemented, bounded changes

- `NovelSources.details` exposes actual source-rule metadata and TOC together. `chapters` remains available as a delegate. No source-specific fabricated metadata, TOC or content is substituted. Raw source intro whitespace is preserved, including 七猫's fullwidth indentation.
- Android detail now follows the existing `NovelWebDetailView`: 100×136 cover; 21sp bold title; author/tags/chapter count; source switch card; source-provided intro/latest; bottom shelf/download/read actions. Native iOS geometry was inspected (54pt navbar, 45pt source card, 58pt rendered CTA height, localized chapter count). Reader and unrelated search/rank/shelf styles remain untouched.
- Native add-to-shelf, download navigation, saved progress resume, source switch and cached-book opening remain wired to production state. Metadata survives offline cache reload; older download save calls do not erase it. Cached books are immediately readable while live metadata refreshes rather than waiting for that network request.
- Android cache counting now scans a book directory once, uses direct hexadecimal SHA-256 formatting, and retains historical cache keys. The prior per-page-turn count repeated book hashing/file stats for all1694 chapters. Chapter replacement requests its scroll reset for the next layout pass instead of forcing immediate remeasure (`requestScrollToItem`, supported by the existing Compose version).
- Android prefetch is neighbor-first (+1, −1), then forward configured range (bounded20) and backward up to5. One failed chapter no longer aborts the remainder.
- Cache loading shares per-key fixed striped locks between foreground/download/prefetch callers, rechecks cache after acquiring a lock, and checks cancellation/session generation before committing a response. A canceled synchronous HTTP call is **not physically aborted**; its eventual response is discarded instead of cached. This is not a claim of full upstream preload equivalence.

## Upstream read-only audit / licensing

Reviewed `Luoyacheng/legado-E` pinned at `8b87c5aba4df91c39a3a0939a68a1180b9f2ee1c`. Upstream LICENSE was read first: GPL-3.0; this repository is also GPLv3. No upstream implementation was copied; the new bounded scheduler is an original implementation of the observed neighbor-first policy. Keep this attribution if porting further behavior.

Pinned reference files under `https://github.com/Luoyacheng/legado-E/blob/8b87c5aba4df91c39a3a0939a68a1180b9f2ee1c/`:

- `app/src/main/java/io/legado/app/data/entities/rule/ExploreKind.kt`: url/text/button/toggle/select/action/chars/default and flex child layout semantics.
- `app/src/main/java/io/legado/app/ui/book/explore/ExploreShowViewModel.kt`: page is advanced only after successful load; failed page remains retryable.
- `app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt` and `AnalyzeUrl.kt`: source rule/script URL and conditional/paged request analysis, reviewed only in this milestone.
- `app/src/main/java/io/legado/app/model/ReadBook.kt` lines938–1024: separate current/neighbor jobs; forward-from+2/backward-from−2 predownload; cancellation and expired job pruning.
- `app/src/main/java/io/legado/app/model/CacheBook.kt`: queue/in-flight deduplication, cached content reuse, cancellation cleanup.
- `app/src/main/java/io/legado/app/data/entities/BookSource.kt`: source configuration/variable model.

## Verification / reproducibility

All native comparison screenshots are actual native app captures, not web/synthetic layout replicas. Real flow: supplied `https://www.yckceo.com/yuedu/shuyuans/json/id/1335.json` → 七猫小说 → 爽文 → 无敌天命 / 青鸾峰上 → 1694 real chapters → 第一章：天命。 Same real book/chapter is used on both platforms.

Mac evidence root: `/Users/edy/Code/rank/parity/`.

- iOS: `ios-reference4.log` and `ios/*.png`, including detail/reader/menu/settings/page-turn/brightness/night/progress/info/TOC. Test production UI is read-only; only UITest selectors and screenshots changed. Earlier `ios-reference3.log` is a **test selector failure**, not an app visual failure: it required digits without thousands separators while the actual native hierarchy showed `共 1,694 章`. Failure hierarchy/attachments retained under `ios-failed-count/`.
- Android: `verified-build.log`, `verified-native-test.log`, `android/native-verified/`. `NovelRealParityTest` imports real live collection and drives ranking → detail → download → reader. It tests cached neighbor availability and offline next/previous reuse. `parity-android-real-flow-current.json` records collection hash/book/TOC, a fresh3815-character chapter response and successful offline next/previous chapter navigation and explicitly says reader parity is incomplete.
- Existing genuine Android BEFORE screenshots from the earlier ranking milestone: `/workspace/iduanju/compare/rank/rank_android_02_real_detail_toc.png` and `rank_android_03_real_reader.png` on the box.
- Core tests: `NovelPrefetchTest` (neighbor bounds, same-key in-flight dedup, cancellation-before-cache, metadata persistence and historical cache-key compatibility); `NovelSourcesTest`; `RealRankRegressionTest` (7 unmodified recorded-source ranking→detail→TOC fixtures:18/28/30/59/65/109/163). Fixture and synthetic scheduling tests are not presented as proof of live native UI success.

### Actual outcomes (not inferred from shell exit status)

- iOS native UI test passed: `ios-reference4.log`,1 test,0 failures,45.791s. The fully loaded detail reference displays `共 1,694 章`.
- Android current production build and real native flow passed: `verified-native-test.log`,1 test,0 failures,47.277s. Collection SHA256 on **both platforms**: `874efe33cbe38b7dcf830704b5bd0614b9485fe1974a20d9c09030ebec07df30`.
- Selected Android core suite:15 tests,13 passed,2 explicitly skipped (optional live environment tests),0 failures/errors. The7 recorded real-source flows passed as one test.
- A second native run (`verified-native-repeat.log`) **failed at initial collection HTTPS download**, before app flow: `SocketTimeoutException` in TLS at test line27. It is not a second successful repetition. Preserve the first passing captures under `android/native-verified`; do not mistake old on-device files for output from this failed repeat. The test now marks evidence incomplete before even starting collection download.
- Earlier expanded reader tests exposed `SnapshotStateObserver`/reentrant layout exceptions and a too-early previous-chapter click while the reader was still busy counting cache files. Their logs are retained (`final-native-test.log`, `final-native-test3.log`, `deferred-layout-native-test.log`). After deferred scroll reset, bounded cache-count work and waiting for enabled controls, the expanded flow passed once. This is not proof of absence of all reader rendering races.
- Own emulator temporarily stopped responding to capture. Only the own rank AVD was restarted (disk preserved), with guest Vulkan disabled. Shared ADB and the other worker's emulator/simulators were not restarted or used.

## Still pending — do not release

1. Android reader must reproduce current good iOS layout/typography/spacing, hidden chrome + overlay panels, palettes, gestures, actual distinct turn modes, TOC/progress/settings/font/brightness/listen interactions. Current raw permanent toolbar is intentionally not falsely called fixed by this detail milestone.
2. Filter rendering/state: both parsers currently only treat button vs URL and omit toggle/select/chars/default/style. 七猫's source-defined button controls currently all enter an86pt rail. Android regenerates categories after actions but retains the old selected category URL/book list/paging snapshot; iOS resets to the first URL category. Need generic stable selection/filter refresh tests with real 1335 sources, not site-specific hardcoding.
3. iOS loader's untracked forward prefetch driver and cancellation-failure behavior still need a bounded functional fix; do not change iOS appearance. Android scheduler is improved but is not a full concurrency/retry/queue port of upstream.
4. No assumption of all-source parity from 七猫 success or the 7 offline fixtures. Existing external 403/502/timeouts and per-source failures remain as documented in `novel-rank-real-source-20261117.md`.

5. Detail source-menu first interaction now matches the reference (current source + 搜索其他书源), but alternative-result chooser presentation and a full interaction/font/dark-theme parity audit are not complete. Do not call the detail milestone pixel-perfect or full module parity. Android reader currently has no replacement for the old detail's per-chapter table; its reference-matching reader TOC/menu must be completed before integration.

Box evidence: `/workspace/iduanju/compare/parity/verified/` and `detail-comparison.png`; archive `native-parity-evidence.zip`. The contact sheet is made only from actual native captures (iOS unchanged / Android before / Android detail milestone), not synthetic app rendering.
