import XCTest
@testable import STV

@MainActor
final class PlayerAdjustTests: XCTestCase {
    func testPortraitOnlyOuterFifths() {
        let w: CGFloat = 400, e: CGFloat = 36
        XCTAssertNil(PlayerAdjuster.zone(x: 20, width: w, landscape: false, edge: e), "edge-back strip")
        XCTAssertEqual(PlayerAdjuster.zone(x: 60, width: w, landscape: false, edge: e), .brightness)
        XCTAssertNil(PlayerAdjuster.zone(x: 81, width: w, landscape: false, edge: e), "middle pages")
        XCTAssertNil(PlayerAdjuster.zone(x: 200, width: w, landscape: false, edge: e))
        XCTAssertNil(PlayerAdjuster.zone(x: 319, width: w, landscape: false, edge: e))
        XCTAssertEqual(PlayerAdjuster.zone(x: 350, width: w, landscape: false, edge: e), .volume)
    }
    func testLandscapeReservesMiddleForEpisodePaging() {
        let w: CGFloat = 900, e: CGFloat = 36
        XCTAssertNil(PlayerAdjuster.zone(x: 10, width: w, landscape: true, edge: e))
        XCTAssertEqual(PlayerAdjuster.zone(x: 100, width: w, landscape: true, edge: e), .brightness)
        for x: CGFloat in [180, 300, 450, 600, 720] {
            XCTAssertNil(PlayerAdjuster.zone(x: x, width: w, landscape: true, edge: e), "middle pages at \(x)")
        }
        XCTAssertEqual(PlayerAdjuster.zone(x: 800, width: w, landscape: true, edge: e), .volume)
        XCTAssertNil(PlayerAdjuster.zone(x: 899, width: w, landscape: true, edge: e), "system edge")
    }
    func testBrightnessClampAndRestore() {
        let a = PlayerAdjuster()
        let orig = UIScreen.main.brightness
        a.begin(.brightness)
        a.change(.brightness, fraction: 5)
        XCTAssertEqual(a.hud?.value, 1)
        a.change(.brightness, fraction: -5)
        XCTAssertEqual(a.hud?.value, 0)
        a.restoreBrightness()
        XCTAssertEqual(UIScreen.main.brightness, orig, accuracy: 0.01)
    }
}
