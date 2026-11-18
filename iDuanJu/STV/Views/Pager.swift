import SwiftUI

@MainActor @Observable
final class Pager {
    var items: [HGSeries] = []
    var hasMore = true
    var isLoading = false
    var error: Error?
    private(set) var page = HGPage(items: [], hasMore: true, nextOffset: 0)
    @ObservationIgnored private var fetch: ((HGPage, [HGSeries]) async throws -> HGPage)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var token = UUID()

    deinit { task?.cancel() }

    func reset(_ fetch: @escaping (HGPage, [HGSeries]) async throws -> HGPage) {
        cancel()
        self.fetch = fetch
        items = []
        hasMore = true
        error = nil
        page = HGPage(items: [], hasMore: true, nextOffset: 0)
        loadMore()
    }

    func cancel() {
        token = UUID()
        task?.cancel()
        task = nil
        isLoading = false
    }

    func loadMore() {
        guard let fetch, hasMore, !isLoading else { return }
        isLoading = true
        error = nil
        let currentToken = token
        let previous = page
        let seen = items
        task = Task { [weak self] in
            defer {
                if let self, self.token == currentToken {
                    self.task = nil
                    self.isLoading = false
                }
            }
            do {
                let response = try await fetch(previous, seen)
                try Task.checkCancellation()
                guard let self, self.token == currentToken else { return }

                var ids = Set(self.items.map(\.id))
                self.items.append(contentsOf: response.items.filter { ids.insert($0.id).inserted })
                self.page = response
                self.hasMore = response.hasMore && !response.items.isEmpty && !Self.repeatedPosition(response, after: previous)
            } catch {
                guard let self, self.token == currentToken, !Task.isCancelled else { return }
                self.error = error
            }
        }
    }

    private static func repeatedPosition(_ response: HGPage, after previous: HGPage) -> Bool {
        guard response.sessionId == previous.sessionId else { return false }
        if let cursor = response.nextCursor { return cursor == previous.nextCursor }
        if let offset = response.nextOffset { return offset == previous.nextOffset }
        return false
    }
}
