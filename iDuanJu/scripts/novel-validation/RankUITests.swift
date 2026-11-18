import XCTest

final class RankUITests: XCTestCase {
    func testSourceConfigurationAndSearchShareNavigation() {
        let app = XCUIApplication()
        app.launchEnvironment["NOVEL_PREVIEW"] = "1"
        app.launchEnvironment["NOVEL_ROUTE"] = "search"
        app.launch()
        XCTAssertTrue(app.navigationBars["小说搜索"].waitForExistence(timeout:10))
        app.buttons["search.sources"].tap()
        XCTAssertTrue(app.navigationBars["书源配置"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["sources.add"].exists)
        app.navigationBars["书源配置"].buttons["返回"].tap()
        let query = app.searchFields.firstMatch
        XCTAssertTrue(query.waitForExistence(timeout:5))
        query.tap(); query.typeText("雾港\n")
        XCTAssertTrue(app.buttons["search.result.雾港"].waitForExistence(timeout:15))
    }
    func testInitialRankCategorySwitchAndDownloadEntry() {
        let app = XCUIApplication()
        app.launchEnvironment["NOVEL_PREVIEW"] = "1"
        app.launch()
        let first = app.buttons["novel.rank.book.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 15), "initial rank must contain fixture books")
        app.buttons["novel.rank.category.畅销榜"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 15), "switching rankings must keep working")
        app.buttons["novel.rank.group.玄幻"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 15), "switching source-defined groups must load books")
        first.tap()
        XCTAssertTrue(app.buttons["detail.read"].waitForExistence(timeout: 10))
        let download = app.buttons.matching(NSPredicate(format: "label CONTAINS '下载'")).firstMatch
        XCTAssertTrue(download.waitForExistence(timeout: 10))
        download.tap()
        XCTAssertTrue(app.navigationBars["缓存与下载"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["缓存后 50 章"].exists)
        app.buttons["缓存后 50 章"].tap()
        XCTAssertTrue(app.staticTexts["下载完成，已可离线阅读"].waitForExistence(timeout:15))
    }
}
