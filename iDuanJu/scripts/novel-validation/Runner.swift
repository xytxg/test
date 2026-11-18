import Foundation

@main struct NovelValidationRunner {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        let sources = try JSONDecoder().decode([LegadoSource].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        let source = sources[Int(args[2])!]
        var report: [String: Any] = ["name": source.bookSourceName, "host": URL(string: source.bookSourceUrl)?.host ?? "", "index": Int(args[2])!]
        func stage(_ name: String, _ work: () throws -> Int) {
            do { report[name] = ["status": "ok", "count": try work()] }
            catch { report[name] = ["status": "failed", "error": String(error.localizedDescription.replacingOccurrences(of: "https?://[^\\s]+", with: "[source URL]", options: .regularExpression).prefix(240))] }
        }
        var categories: [LegadoClient.ExploreCategory] = []
        stage("categories") { categories = try LegadoClient.exploreCategories(source); return categories.count }
        if args.count > 3 && args[3] == "live" {
            var hits: [LegadoSearchItem] = []
            if let category = categories.first(where: { $0.action == nil && !$0.url.isEmpty }) {
                stage("explore") { hits = try LegadoClient.explore(source, category: category); guard !hits.isEmpty else { throw LegadoError.empty("empty book list") }; return hits.count }
            }
            var searchHits: [LegadoSearchItem] = []
            let keyword = source.bookSourceName == "七猫小说" ? "都市" : (source.ruleSearch?["checkKeyWord"].flatMap { $0.isEmpty ? nil : $0 } ?? "西游记")
            report["keyword"] = keyword
            stage("search") { searchHits = try LegadoClient.search(source, key: keyword); guard !searchHits.isEmpty else { throw LegadoError.empty("empty search result") }; return searchHits.count }
            if let hit = searchHits.first ?? hits.first {
                report["bookTitle"] = hit.name
                var info: LegadoBookInfo?
                var toc: [LegadoChapter] = []
                stage("detail") { info = try LegadoClient.info(source, bookURL: hit.bookURL); return info!.name.count }
                stage("toc") { toc = try LegadoClient.toc(source, tocURL: info?.tocURL ?? hit.bookURL, book: ["name": hit.name, "bookUrl": hit.bookURL]); guard !toc.isEmpty else { throw LegadoError.empty("empty chapter list") }; return toc.count }
                if !toc.isEmpty {
                    if ["番茄小说", "书旗小说"].contains(source.bookSourceName) {
                        var texts: [String] = []
                        for i in 0..<min(3, toc.count) {
                            stage("chapter\(i + 1)") {
                                let text = try LegadoClient.content(source, chapter: toc[i], nextChapterURL: i+1 < toc.count ? toc[i+1].url : nil, book: ["name": hit.name, "bookUrl": hit.bookURL])
                                guard text.count > 300 else { throw LegadoError.empty("正文过短，不能记作阅读通过") }
                                texts.append(text); return text.count
                            }
                        }
                        stage("offlineCache") {
                            guard texts.count == min(3,toc.count) else { throw LegadoError.empty("前三章正文未全部通过") }
                            let store = NovelStore.shared
                            let book = store.addWeb(hit, info: info, toc: toc)
                            defer { store.remove(book) }
                            for (i,text) in texts.enumerated() { try store.cache(book,i,text) }
                            LegadoHTTP.transport = { _ in throw URLError(.notConnectedToInternet) }
                            defer { LegadoHTTP.transport = nil }
                            for (i,text) in texts.enumerated() {
                                guard store.chapterText(book,i) == text else { throw LegadoError.empty("离线缓存回读不一致") }
                            }
                            return store.cachedCount(book)
                        }
                    }
                    stage("content") {
                        var last: Error = LegadoError.empty("no readable sample chapter")
                        for (index, chapter) in toc.prefix(3).enumerated() {
                            do {
                                let text = try LegadoClient.content(source, chapter: chapter, nextChapterURL: index + 1 < toc.count ? toc[index + 1].url : nil, book: ["name": hit.name, "bookUrl": hit.bookURL])
                                guard text.count > 80 else { throw LegadoError.empty("body too short") }
                                report["contentChapterIndex"] = index
                                return text.count
                            } catch { last = error }
                        }
                        throw last
                    }
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
