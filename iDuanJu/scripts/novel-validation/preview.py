"""Small simulator app using production novel views/engine (no player dependencies)."""
from pathlib import Path
import json
import shutil
import sys

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
shutil.copytree(root / 'STV/Novel', out / 'Novel', dirs_exist_ok=True)
shutil.copyfile(root / 'STV/Views/Theme.swift', out / 'Theme.swift')
html = (root / 'STV/Plugins/PluginHTML.swift').read_text('utf8')
(out / 'CSSXPath.swift').write_text(html[:html.index('/// libxml2 HTML documents')], 'utf8')
shutil.copytree(root / 'STVTests/Fixtures/legado', out / 'Fixtures/legado', dirs_exist_ok=True)
tests = out / 'Tests'
tests.mkdir(exist_ok=True)
(out / 'UITests').mkdir(exist_ok=True)
shutil.copyfile(root / 'scripts/novel-validation/RankUITests.swift', out / 'UITests/RankUITests.swift')
for name in ['LegadoTests.swift', 'NovelSourceBundleTests.swift', 'NovelCacheTests.swift']:
    if (root / 'STVTests' / name).exists():
        shutil.copyfile(root / 'STVTests' / name, tests / name)
(out / 'project.yml').write_text(f'''name: NovelPreview
options:
  deploymentTarget:
    iOS: "18.0"
settings:
  SWIFT_VERSION: "5.0"
packages:
  QuickJS:
    path: {root / 'Packages/QuickJS'}
targets:
  STV:
    type: application
    platform: iOS
    sources:
      - Novel
      - Theme.swift
      - CSSXPath.swift
      - PreviewApp.swift
    dependencies:
      - package: QuickJS
        product: CQuickJS
    info:
      path: PreviewInfo.plist
      properties:
        CFBundleDisplayName: Novel Preview
        UILaunchScreen: {{}}
        NSAppTransportSecurity:
          NSAllowsArbitraryLoads: true
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: app.iduanju.novelpreview
      GENERATE_INFOPLIST_FILE: YES
  STVTests:
    type: bundle.unit-test
    platform: iOS
    sources: [Tests]
    dependencies:
      - target: STV
    settings:
      GENERATE_INFOPLIST_FILE: YES
  NovelUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [UITests]
    dependencies:
      - target: STV
    settings:
      GENERATE_INFOPLIST_FILE: YES
      TEST_TARGET_NAME: STV
schemes:
  STV:
    build:
      targets:
        STV: all
        STVTests: [test]
        NovelUITests: [test]
    test:
      targets: [STVTests, NovelUITests]
''', 'utf8')
(out / 'PreviewApp.swift').write_text('''import SwiftUI
@main struct PreviewApp: App {
    private static let previewItem = LegadoSearchItem(name: "雾港", author: "测试作者", kind: "奇幻 · 连载", intro: "仅用于界面验收的合成书籍。", cover: "", latest: "第 200 章", bookURL: "https://preview.invalid/book/0", sourceURL: "https://preview.invalid", sourceName: "界面验收 · 合成数据")
    init() {
        if ProcessInfo.processInfo.environment["NOVEL_PREVIEW"] == "1" {
            let source = LegadoSource(bookSourceUrl: "https://preview.invalid", bookSourceName: "界面验收 · 合成数据", searchUrl: "/search", ruleSearch: ["bookList": "$.books[*]", "name": "$.name", "bookUrl": "$.url", "author": "$.author", "kind": "$.kind"], ruleBookInfo: ["name": "$.name", "author": "$.author", "tocUrl": "$.toc"], ruleToc: ["chapterList": "$.chapters[*]", "chapterName": "$.title", "chapterUrl": "$.url"], ruleContent: ["content": "$.content"])
            var s = source
            s.exploreUrl = "全部::\\n月票榜::/rank/month\\n畅销榜::/rank/sales\\n新书榜::/rank/new\\n完结榜::/rank/end\\n追读榜::/rank/read\\n玄幻::\\n热门榜::/fantasy"
            LegadoSourceStore.shared.remove(Set(LegadoSourceStore.shared.sources.map(\\.id)))
            LegadoSourceStore.shared.add([s])
            LegadoHTTP.transport = { req in
                let books = ["雾港", "灯塔来信", "长夜星河", "山海之间", "云中书", "远方有风"].enumerated().map { i,t in ["name": t, "author": "测试作者", "kind": "奇幻 · 连载", "url": "https://preview.invalid/book/\\(i)"] }
                let chapters = (0..<200).map { ["title": "第\\($0+1)章", "url": "https://preview.invalid/chapter/\\($0)"] }
                let data = try JSONSerialization.data(withJSONObject: ["books": books, "name": "雾港", "author": "测试作者", "toc": "https://preview.invalid/toc", "chapters": chapters, "content": "合成离线正文"] as [String: Any])
                return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            if ProcessInfo.processInfo.environment["NOVEL_ROUTE"] == "download" {
                let toc = (0..<200).map { LegadoChapter(title: "第\\($0+1)章", url: "https://preview.invalid/chapter/\\($0)") }
                let book = NovelStore.shared.addWeb(Self.previewItem, info: nil, toc: toc)
                for i in 0..<24 { try? NovelStore.shared.cache(book, i, "合成离线正文") }
            }
        }
    }
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.environment["NOVEL_ROUTE"] == "detail" {
                NavigationStack { NovelWebDetailView(items: [Self.previewItem], onRead: { _ in }) }
            } else if ProcessInfo.processInfo.environment["NOVEL_ROUTE"] == "download", let book = NovelStore.shared.webBook(source: Self.previewItem.sourceURL, url: Self.previewItem.bookURL) {
                NovelDownloadView(book: book)
            } else if ProcessInfo.processInfo.environment["NOVEL_ROUTE"] == "sources" {
                NovelSourcesView()
            } else if ProcessInfo.processInfo.environment["NOVEL_ROUTE"] == "search" {
                NovelSearchView(onRead: { _ in })
            } else { NovelExploreView(onRead: { _ in }) }
        }
    }
}
''', 'utf8')
