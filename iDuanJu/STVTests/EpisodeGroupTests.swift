import XCTest
@testable import STV

final class EpisodeGroupTests: XCTestCase {
    func testRedesignThirtyEpisodeGroups() {
        XCTAssertEqual(EpisodeGroups.ranges(total: 0), [])
        XCTAssertEqual(EpisodeGroups.ranges(total: 30), [EpisodeRange(0,29)])
        XCTAssertEqual(EpisodeGroups.ranges(total: 48), [EpisodeRange(0,29),EpisodeRange(30,47)])
        XCTAssertEqual(EpisodeGroups.ranges(total: 60), [EpisodeRange(0,29),EpisodeRange(30,59)])
        XCTAssertEqual(EpisodeGroups.size(for: 301), 50)
        XCTAssertEqual(EpisodeGroups.size(for: 601), 60)
    }
}
