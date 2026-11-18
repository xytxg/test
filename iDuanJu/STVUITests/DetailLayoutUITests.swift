import XCTest

/// Native, clearly labelled sparse-data fixture: no made-up missing rating or heat fields.
final class DetailLayoutUITests: XCTestCase {
    func testSparseMetricsAndScrolledLayout() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchEnvironment = ["STV_ROUTE": "detail:ui-detail-sparse"]
        app.launch()
        let stats = app.descendants(matching: .any)["detail.stats"].firstMatch
        XCTAssertTrue(stats.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(stats.frame.height, 64, "Sparse metric card must never expand vertically")
        XCTAssertTrue(app.staticTexts["40.3 万"].exists)
        XCTAssertFalse(app.staticTexts["观众评分"].exists)
        XCTAssertFalse(app.staticTexts["全网热度"].exists)
        app.buttons["31-48"].firstMatch.tap()
        app.swipeUp()
        sleep(2)
        let bar = app.descendants(matching: .any)["detail.playbar"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 4))
        let att = XCTAttachment(screenshot: app.screenshot()); att.name = "detail-scrolled-native"; att.lifetime = .keepAlways; add(att)
        print("DETAIL_SCROLLED_READY"); sleep(5)
    }
}
