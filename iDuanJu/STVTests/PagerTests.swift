import XCTest
@testable import STV

final class PagerTests: XCTestCase {
    @MainActor func testRepeatedCursorStopsPagingAndDeduplicatesItems() async throws {
        let pager = Pager()
        let first = HGSeries(seriesId: "1", title: "First", cover: "")
        let second = HGSeries(seriesId: "2", title: "Second", cover: "")
        pager.reset { previous, _ in
            let items = previous.nextCursor == nil ? [first] : [first, second, second]
            return HGPage(items: items, hasMore: true, nextCursor: "page-2")
        }
        try await waitForPage(pager)
        XCTAssertTrue(pager.hasMore)
        pager.loadMore()
        try await waitForPage(pager)
        XCTAssertEqual(pager.items.map(\.seriesId), ["1", "2"])
        XCTAssertFalse(pager.hasMore)
    }

    @MainActor func testResetCancelsOldPageAndKeepsNewResults() async throws {
        let pager = Pager()
        let first = HGSeries(seriesId: "old", title: "Old", cover: "")
        let second = HGSeries(seriesId: "new", title: "New", cover: "")
        var oldStarted = false
        pager.reset { _, _ in
            oldStarted = true
            try await Task.sleep(for: .seconds(2))
            return HGPage(items: [first], hasMore: false)
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !oldStarted && clock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(oldStarted)
        pager.reset { _, _ in HGPage(items: [second], hasMore: false) }
        try await waitForPage(pager)
        XCTAssertEqual(pager.items.map(\.seriesId), ["new"])
        XCTAssertNil(pager.error)
    }

    @MainActor private func waitForPage(_ pager: Pager) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while pager.isLoading && clock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(pager.isLoading)
    }
}
