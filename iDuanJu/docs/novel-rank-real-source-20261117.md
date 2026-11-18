# Real-source ranking compatibility — 2026-11-17

## Scope and status

User source: https://www.yckceo.com/yuedu/shuyuans/json/id/1335.json

Branch `codex/novel-rank-fix`, isolated `~/code/Iduanju-rank`. No merge/release/push/PR: publication is held pending coordinated UI corrections. No unrelated checkout/device was modified.

The collection has 164 entries, 105 text sources with nonempty discovery rules. Each full scan tries page 1 of the first three non-action categories, including disabled sources. **List success is not a guarantee that every book/content works.**

| Production engine probe | Before | After |
|---|---:|---:|
| iOS (macOS executable of engine) | 35/105 | 63/105 |
| Android (JVM, production Rhino/Jsoup engine) | 36/105 | 68/105 |

Raw before/after results: `scripts/novel-validation/rank-*-before.json`, `rank-*-final.json`. These are observed site responses, not an assertion that failures are all engine defects.

## Root causes / changes

- iOS dropped empty page alternatives (`<,_{{page}}>`), ignored CSS segment indexes (`a.0`), and excluded the current node from Jsoup-style selectors. Real sources then returned no books or malformed multi-line URLs. Fix generic page/index/self-match semantics and getString0-like URL selection.
- Item-scoped XPath was evaluated as a whole-page XPath. CSS `nth-child(even)` was unsupported. Implement scoped XPath and general An+B conversion.
- `getString` wrongly passed lists to JS; leading JS on a JSON item must instead preserve the object. Preserve that distinction; support element collections for TOC JS (`result.toArray()`, `el.attr()`) and analyzer `src`. The preexisting JS-list test now uses getStringList, with an explicit getString/String regression assertion.
- Android lacked Jsoup host methods, implicit JSON paths, list operators/segment indexes, current-element attributes, source JS headers and charset detection. Optional metadata errors discarded complete books. Add the shared compatibility surface instead of site-specific branches.
- Shared JS compatibility: URL-map `jsLib`, `infoMap`, hex bytes, StrResponse + source `loginCheckJs`, Java collections and case-insensitive PKCS7 padding alias. 点众 encrypts headers/requests and decrypts responses; omitting any one of these produced empty/duplicate lists.
- Discovery JSON needs Gson-style raw-control leniency. Titles contain invisible formatting characters. Public IP literal source URLs must not be treated as private; private addresses remain rejected.
- Remember the chosen ranking source on both platforms; revisiting no longer silently resets to the first, Cloudflare-blocked source. No site is special-cased.

Primary production files: `STV/Novel/Legado/{LegadoClient,LegadoCore,LegadoRule,LegadoSource,NovelExploreView}.swift`, `STV/Plugins/PluginHTML.swift`, Android `NovelSources.kt`, `NovelScript.kt`, generated `novel-prelude.js`, `NovelScreen.kt`.

## Tests and visible evidence

- iOS: LegadoTests + NovelSourceBundleTests + RealRankRegressionTests: 22 tests, 0 failures, 1 optional collection test skipped. Includes real live rank → detail → TOC on 七猫/爱看/飘天/点众.
- Android: NovelSourcesTest + NovelCacheTest + RealRankRegressionTest: 11 tests, 0 failures, 1 existing optional bundle test skipped. Real live flow on the same four sources passed.
- Seven offline fixtures are captured public list/detail/TOC responses with unchanged source rules: indexes 18,28,30,59,65,109,163. Expected nonempty books and multiple chapters on each. URLs/status/content types/redirect URLs are recorded. No synthetic result books.
- iOS live UI on isolated iPhone 17 simulator `E258CA6F-4207-4AB4-A893-40F9F58F9A20`, own DerivedData: imported the actual collection; selected 七猫 → 爽文 → 无敌天命 → loaded detail/1694 chapters → reader → real TOC. XCTest passed.
- Android live UI on isolated `iduanju_rank`, `emulator-5556`: imported the exact URL through the app (159 supported sources); selected 七猫 → 爽文 → 无敌天命 → combined detail/TOC with 1694 chapters.
- Screenshots are copied to box `/workspace/iduanju/compare/rank/`: `rank_ios_01_real_categories_books.png`, `rank_ios_02_real_detail.png`, `rank_ios_03_real_toc.png`, `rank_android_01_real_categories_books.png`, `rank_android_02_real_detail_toc.png`. Android detail and TOC are one existing screen, not a separate fabricated detail view.

### Reproduce

- Offline Android: `JAVA_HOME=<JDK21> ./android/gradlew -p android :core:test --tests '*Novel*Test' --tests '*RealRank*'`.
- Opt-in live Android: same command with `STV_RANK_LIVE=/absolute/path/1335.json` and `--rerun-tasks`.
- iOS: `xcodebuild -project STV.xcodeproj -scheme STV -destination 'platform=iOS Simulator,id=<isolated-UDID>' -derivedDataPath <own-DD> test -only-testing:STVTests/LegadoTests -only-testing:STVTests/NovelSourceBundleTests -only-testing:STVTests/RealRankRegressionTests CODE_SIGNING_ALLOWED=NO`.
- Live iOS uses `TEST_RUNNER_STV_RANK_LIVE=<canonical absolute path>`; UI test is `STVUITests/NovelUITests/testLiveRealRankToDetailAndTOC`, screenshots via `TEST_RUNNER_STV_SHOT_DIR=<directory>`. Case of the host path matters inside Simulator.
- `RankProbe.swift` can be compiled with the engine using existing `prepare.py`; `rank-drive.py <executable> <collection> <output>` scans the collection. Android equivalent: `rank-android-drive.py <classpath-file> <collection> <output>`, class `app.iduanju.core.NovelRankProbe`. `RECORD_DETAIL=1` checks TOC as well.

## Remaining failures / limits

- The first source 猫扑 returns Cloudflare HTTP 403. It was NOT bypassed. Selecting another source is necessary on a fresh install.
- Many .la/.info endpoints return HTTP 502 from this Mac/Clash network; several sites return certificate/TLS errors. These remain failed, not converted to empty success.
- iOS-only URLSession timeouts remain on source indexes 145,146,152,153,162 while Android gets books. Cause not fully isolated; do not claim engine/network parity. No TLS verification was disabled.
- Index 6 returns no books; index 160 produces baidu.com URLs/404 from its supplied rules.
- Full scans only prove listing extraction. 月色 (154) lists books but its decoded TOC URLs are not yet reliably correct; this remains open. Other books/content/paywalls were not exhaustively verified.

### Every source with no books in the final scan

| Index | Source | iOS | Android | Observed first failure |
|---:|---|---|---|---|
| 1 | 猫扑中文 | failed | failed | HTTP 403：https://m.bookmaopu.com/1.html?page=1 |
| 2 | 优质粉鲍 | failed | failed | 网络错误：The request timed out. |
| 6 | 黄区 | failed | failed | zero books |
| 15 | 八月文学 | failed | failed | HTTP 502：http://www.jiuxs.la/shu/1-default-0-0-0-0-2-0-1.html |
| 16 | 乐库小说 | failed | failed | HTTP 502：http://m.6lk.la/sort/1/1.html |
| 19 | ️读趣网站 | failed | failed | HTTP 502：http://www.xduqu.com/modules/article/articlefilter.php?&order=lastupdate&page=1 |
| 20 | 无双小说 | failed | failed | HTTP 502：http://www.buxia.la/mulu/1/1.html |
| 22 | 键盘小说 | failed | failed | HTTP 502：http://www.janpn.org/xuanhuanqihuan/list-1-1.html |
| 26 | ️快眼小说 | failed | failed | HTTP 502：http://www.kyxsw.info/fenlei1_1.html |
| 29 | 鸟书网 | failed | failed | HTTP 502：http://wap.99wx.info/ |
| 33 | ️三叉小说 | failed | failed | 书源规则错误：JS：HTTP 502：http://m.xxxbiquge.net/xclass/0/1.html |
| 40 | 武道文学 | failed | failed | HTTP 502：http://www.bookwenxue.com/class/1_1.html |
| 43 | 三五中文 | failed | failed | HTTP 502：http://www.xkushu.org/zwwsort1/0/1.htm |
| 46 | 美艺言情 | failed | failed | HTTP 502：http://m.meiyeewk.com/list/ |
| 55 | 求书网 | failed | failed | HTTP 502：http://www.qiushu.info/top/allvote.html |
| 61 | 就爱文学 | failed | failed | HTTP 502：http://www.92xs.info/allvisit-1.html |
| 63 | 女生文学 | failed | failed | HTTP 502：http://www.xwenxuem.com/book/topweekvisit/0/1.html |
| 64 | 手机小说 | failed | failed | HTTP 502：http://www.sjshuku.com/soft/1/Soft_001_1.html |
| 76 | 77读书网 | failed | failed | HTTP 502：http://www.77shuku.info/store/1_1.html |
| 77 | 悠久小说 | failed | failed | HTTP 502：http://www.ujxsw.org/xuanhuan/1/ |
| 80 | 永恒小说 | failed | failed | 书源规则错误：JS：HTTP 502：http://wap.4pan.org/mulu/ |
| 83 | 鬼吹灯 | failed | failed | HTTP 502：http://m.cxzz958.com/wanben/1.html |
| 86 | 爱笔楼 | failed | failed | HTTP 502：http://m.biqutu.info/ph/week1.html |
| 87 | 棉花糖 | failed | failed | HTTP 502：http://www.mhtxs.info/mulu/1-1.html |
| 91 | 文桑小说 | failed | failed | HTTP 502：http://www.wensang.net/xuanhuan/page_1.html |
| 93 | 阅读书库 | failed | failed | HTTP 502：http://www.yeudusk.com/book/sort1/0/1.html |
| 96 | 玄幻阁吧 | failed | failed | HTTP 502：http://www.xuanhuange.info/sort1/1/ |
| 101 | 八一中文 | failed | failed | HTTP 502：http://www.81shuku.info/xuanhuanxiaoshuo/1_1.html |
| 103 | 笔趣阁 | failed | failed | 网络错误：The request timed out. |
| 110 | 笔趣中文 | failed | failed | HTTP 502：http://m.ibiquzw.org/xclass/0/1.html |
| 113 | 亿软小说 | failed | failed | HTTP 502：http://m.iyruan.info/sort/1/1.html |
| 116 | 亿软小说 | failed | failed | HTTP 502：http://m.yruan.com/sort/1/1.html |
| 119 | 鬼吹灯 | failed | failed | HTTP 502：http://www.gdbzkz.la/fenlei/1/1.html |
| 124 | 玄幻阁吧 | failed | failed | HTTP 502：http://www.xuanyge.net/sort1/1/ |
| 127 | 黄易小说 | failed | failed | HTTP 502：http://wap.aihytd.com/ph/week0.html |
| 128 | 免费小说 | failed | failed | 网络错误：The certificate for this server is invalid. You might be connecting to a server that is pretending to be “www.quanwenyue |
| 145 | ️BL书阁️ | failed | books | 网络错误：The request timed out. |
| 146 | 耽美小说 | failed | books | 网络错误：The request timed out. |
| 152 | 肉文NP | failed | books | 网络错误：The request timed out. |
| 153 | 夜书吧 | failed | books | 网络错误：The request timed out. |
| 160 | 书耽 | failed | failed | HTTP 404：https://www.baidu.com/category_type=1&order=week_click&page=1 |
| 162 | PO18文学 | failed | books | 网络错误：The request timed out. |
