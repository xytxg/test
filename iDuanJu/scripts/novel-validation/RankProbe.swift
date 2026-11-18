import Foundation

/// Explore-only probe: categories + first page of up to N categories for one source.
@main struct RankProbe {
    static func main() throws {
        let args = CommandLine.arguments
        let sources = try LegadoSourceStore.parse(Data(contentsOf: URL(fileURLWithPath: args[1])))
        let source = sources[Int(args[2])!]
        let limit = args.count > 3 ? Int(args[3])! : 3
        if let dir = ProcessInfo.processInfo.environment["RECORD"] { Recorder.install(dir) }
        var report: [String: Any] = ["index": Int(args[2])!, "name": source.bookSourceName]
        do {
            let cats = try LegadoClient.exploreCategories(source)
            report["categories"] = cats.count
            report["groups"] = Array(Set(cats.map(\.group))).sorted()
            var res: [[String: Any]] = []
            for c in cats.filter({ $0.action == nil && !$0.url.isEmpty }).prefix(limit) {
                let t = Date()
                do {
                    let items = try LegadoClient.explore(source, category: c, page: 1)
                    if ProcessInfo.processInfo.environment["RECORD_DETAIL"] == "1", let b = items.first, res.isEmpty {
                        let info = try LegadoClient.info(source, bookURL: b.bookURL)
                        let toc = try LegadoClient.toc(source, tocURL: info.tocURL)
                        report["detail"] = ["name": info.name, "author": info.author, "toc": toc.count, "first": toc.first?.title ?? "", "urls": Set(toc.map(\.url)).count, "firstURL": toc.first?.url ?? ""]
                    }
                    res.append(["title": c.title, "count": items.count, "first": items.first.map { "\($0.name)|\($0.bookURL)" } ?? "", "ms": Int(Date().timeIntervalSince(t)*1000)])
                } catch { res.append(["title": c.title, "url": String(c.url.prefix(160)), "error": String("\(error.localizedDescription)".prefix(300))]) }
            }
            report["explore"] = res
        } catch { report["catError"] = String("\(error.localizedDescription)".prefix(300)) }
        print(String(decoding: try JSONSerialization.data(withJSONObject: report), as: UTF8.self))
    }
}

enum Recorder {
    nonisolated(unsafe) static var routes: [[String: Any]] = []
    static func install(_ dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        LegadoHTTP.transport = { req in
            let sem = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var out: (Data?, URLResponse?, Error?)
            URLSession.shared.dataTask(with: req) { d, r, e in out = (d, r, e); sem.signal() }.resume()
            sem.wait()
            if let e = out.2 { throw e }
            let r = out.1 as! HTTPURLResponse, d = out.0 ?? Data()
            let file = String(format: "%03d.bin", routes.count)
            try d.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
            routes.append(["method": req.httpMethod ?? "GET", "url": req.url!.absoluteString, "body": String(decoding: req.httpBody ?? Data(), as: UTF8.self),
                           "responseURL": r.url?.absoluteString ?? req.url!.absoluteString, "status": r.statusCode, "contentType": r.value(forHTTPHeaderField: "Content-Type") ?? "", "file": file])
            try JSONSerialization.data(withJSONObject: routes, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: dir).appendingPathComponent("routes.json"))
            // Replay with the final URL so relative links resolve the same way.
            return (d, HTTPURLResponse(url: r.url ?? req.url!, statusCode: r.statusCode, httpVersion: nil, headerFields: ["Content-Type": r.value(forHTTPHeaderField: "Content-Type") ?? ""])!)
        }
    }
}
