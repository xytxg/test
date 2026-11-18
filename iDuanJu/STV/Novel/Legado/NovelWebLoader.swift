import Foundation
import Observation

/// Fetches 书源 chapters on demand (and the next ones ahead of the reader), caching them on disk.
@MainActor @Observable
final class NovelWebLoader {
    static let shared = NovelWebLoader()
    /// Bumped whenever a chapter arrives or fails, so open readers re-paginate.
    private(set) var revision = 0
    private(set) var failed: [String: String] = [:]
    @ObservationIgnored private var running: [String: Task<Void, Error>] = [:]
    @ObservationIgnored private var prefetchDrivers: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var speculative: [String: Set<String>] = [:]
    @ObservationIgnored private var demand: [String: Set<UUID>] = [:]
    @ObservationIgnored private var readerRequests: [String: [String: Task<Void, Never>]] = [:]
    @ObservationIgnored private var prefetchFailures: [String: Int] = [:]
    @ObservationIgnored private var activeReaderBook: String?
    @ObservationIgnored private var downloads: [String: Task<Void, Never>] = [:]
    struct DownloadState {
        var completed = 0
        var total = 0
        var failures = 0
        var active = false
        var message = ""
    }
    private(set) var downloadStates: [String: DownloadState] = [:]
    private let store = NovelStore.shared

    private func key(_ b: NovelBook, _ i: Int) -> String { NovelStore.chapterFile(b, i).path }

    func error(_ b: NovelBook, _ i: Int) -> String? { failed[key(b, i)] }
    func isLoading(_ b: NovelBook, _ i: Int) -> Bool { running[key(b, i)] != nil }

    func ensure(_ b: NovelBook, _ i: Int) {
        guard b.isWeb, b.chapters.indices.contains(i), !store.isCached(b, i) else { return }
        let k = key(b, i)
        guard running[k] == nil, failed[k] == nil else { return }
        readerRequests[b.id, default: [:]][k] = Task {
            defer { readerRequests[b.id]?[k] = nil }
            try? await load(b, i)
        }
    }

    func load(_ b: NovelBook, _ i: Int, speculativeOnly: Bool = false) async throws {
        guard b.isWeb, b.chapters.indices.contains(i), !store.isCached(b, i) else { return }
        let k = key(b, i)
        try Task.checkCancellation()
        let owner = UUID()
        if !speculativeOnly { demand[k, default: []].insert(owner) }
        defer { demand[k]?.remove(owner); if demand[k]?.isEmpty == true { demand[k] = nil } }
        func wait(_ task: Task<Void, Error>) async throws {
            try await withTaskCancellationHandler {
                try await task.value
                try Task.checkCancellation()
            } onCancel: {
                guard !speculativeOnly else { return }
                Task { @MainActor in
                    self.demand[k]?.remove(owner)
                    if self.demand[k]?.isEmpty != false { task.cancel() }
                }
            }
        }
        if let task = running[k] { return try await wait(task) }
        guard let source = LegadoSourceStore.shared.source(b.sourceURL ?? ""), let urls = b.chapterURLs, urls.indices.contains(i) else {
            failed[k] = "书源已删除，无法加载"
            revision += 1
            throw LegadoError.empty("书源已删除，无法加载")
        }
        let chapter = LegadoChapter(title: b.chapters[i].title, url: urls[i])
        let next = urls.indices.contains(i + 1) ? urls[i + 1] : nil
        let bookInfo: [String: Any] = ["name": b.title, "author": b.author ?? "", "bookUrl": b.bookURL ?? "", "tocUrl": b.tocURL ?? ""]
        nonisolated(unsafe) let info = bookInfo
        let task = Task<Void, Error> {
            do {
                let text = try await LegadoClient.run { try LegadoClient.content(source, chapter: chapter, nextChapterURL: next, book: info) }
                // Chapter heading first, like imported books, so the reader styles it.
                let full = text.hasPrefix(chapter.title) ? text : chapter.title + "\n" + text
                try Task.checkCancellation()
                guard store.book(b.id) != nil else { throw CancellationError() }
                try store.cache(b, i, full)
                failed[k] = nil
            } catch {
                if error is CancellationError || Task.isCancelled { failed[k] = nil }
                else { failed[k] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
                throw error
            }
        }
        running[k] = task
        defer { running[k] = nil; revision += 1 }
        try await wait(task)
    }

    func retry(_ b: NovelBook, _ i: Int) {
        failed[key(b, i)] = nil
        ensure(b, i)
        revision += 1
    }

    /// Same bounded neighbor-first policy as the Android implementation; no UI appearance changes.
    static func prefetchIndices(around i: Int, total: Int, count: Int) -> [Int] {
        guard (0..<total).contains(i), count > 0 else { return [] }
        let forward = min(20, count)
        var result = [i + 1, i - 1]
        if forward >= 2 { result += (2...forward).map { i + $0 } }
        if min(5, forward) >= 2 { result += (2...min(5, forward)).map { i - $0 } }
        var seen = Set<Int>()
        return result.filter { (0..<total).contains($0) && seen.insert($0).inserted }
    }

    func cancelPrefetch(_ book: NovelBook) { cancelReader(book.id, keeping: []) }

    private func cancelReader(_ id: String, keeping: Set<String>) {
        prefetchDrivers[id]?.cancel(); prefetchDrivers[id] = nil
        for k in speculative[id] ?? [] where !keeping.contains(k) && demand[k]?.isEmpty != false { running[k]?.cancel() }
        speculative[id] = speculative[id]?.intersection(keeping)
        for (k, task) in readerRequests[id] ?? [:] where !keeping.contains(k) { task.cancel() }
    }

    func prefetch(_ b: NovelBook, around i: Int) {
        if let old = activeReaderBook, old != b.id { cancelReader(old, keeping: []) }
        activeReaderBook = b.id
        let count = min(20, max(0, UserDefaults.standard.object(forKey: "novel.prefetch") as? Int ?? 3))
        let indices = Self.prefetchIndices(around: i, total: b.chapters.count, count: count)
        let wanted = Set(([i] + indices).filter { b.chapters.indices.contains($0) }.map { key(b, $0) })
        cancelReader(b.id, keeping: wanted)
        ensure(b, i)
        guard !indices.isEmpty else { return }
        prefetchDrivers[b.id] = Task {
            for j in indices {
                guard !Task.isCancelled, store.book(b.id) != nil else { return }
                let k = key(b, j)
                guard prefetchFailures[k, default: 0] < 3 else { continue }
                speculative[b.id, default: []].insert(k)
                do { try await load(b, j, speculativeOnly: true); prefetchFailures[k] = nil }
                catch is CancellationError { return }
                catch { prefetchFailures[k, default: 0] += 1 }
                speculative[b.id]?.remove(k)
            }
        }
    }

    func download(_ book: NovelBook, from: Int, count: Int?) {
        guard downloads[book.id] == nil, !book.chapters.isEmpty else { return }
        let start = min(max(0, from), book.chapters.count)
        let end = count.map { min(book.chapters.count, start + max(0, $0)) } ?? book.chapters.count
        downloadStates[book.id] = DownloadState(total: end - start, active: true)
        downloads[book.id] = Task {
            defer { downloads[book.id] = nil; downloadStates[book.id]?.active = false }
            for i in start..<end {
                if Task.isCancelled || store.book(book.id) == nil { downloadStates[book.id]?.message = "已暂停，可继续下载"; return }
                do {
                    try await load(book, i)
                    downloadStates[book.id]?.completed += 1
                } catch {
                    downloadStates[book.id]?.failures += 1
                    downloadStates[book.id]?.message = error.localizedDescription
                    // A blocked/login-required source must not fan out across an entire book.
                    return
                }
            }
            if downloadStates[book.id]?.failures == 0 { downloadStates[book.id]?.message = "下载完成，已可离线阅读" }
        }
    }

    func stopDownload(_ book: NovelBook) { downloads[book.id]?.cancel() }

    /// Re-reads the 目录 (new chapters of an ongoing book). Returns the new chapter count.
    func refreshToc(_ b: NovelBook) async throws -> Int {
        guard let source = LegadoSourceStore.shared.source(b.sourceURL ?? ""), let toc = b.tocURL else { return b.chapters.count }
        let book = ["name": b.title, "author": b.author ?? "", "bookUrl": b.bookURL ?? "", "tocUrl": toc]
        let list = try await LegadoClient.run { try LegadoClient.toc(source, tocURL: toc, book: book) }
        if list.count >= b.chapters.count { store.updateToc(b, list) }
        return list.count
    }
}
