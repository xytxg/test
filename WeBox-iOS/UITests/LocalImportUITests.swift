import XCTest

final class LocalImportUITests: XCTestCase {
    @MainActor func testPickLocalFileFirstImportAndVisibleFailure() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let script = "WeBox.define({api:'1.5',id:'test.local.ui',name:'本地文件验证',version:'1.0.0',filters:async()=>[],list:async()=>({items:[],nextCursor:null}),detail:async()=>({}),play:async()=>({sources:[]})});"
        let data = Data([0xff, 0xfe]) + script.data(using: .utf16LittleEndian)!
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "--import-test-document", data.base64EncodedString()]
        app.launch()
        XCTAssertTrue(app.buttons["添加内容源"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["添加内容源"].tap()
        XCTAssertTrue(app.buttons["import-local-js"].waitForExistence(timeout: 10))
        app.buttons["import-local-js"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 25), app.debugDescription)
        cancel.tap()
        let importButton = app.buttons["import-local-js"]
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: importButton)
        XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 20), .completed)
        XCTAssertFalse(app.buttons["清除导入结果"].exists)
        importButton.tap()
        try choose("Local-UTF16.webox.js", app: app)
        XCTAssertTrue(app.staticTexts["已添加到内容源"].waitForExistence(timeout: 35), app.debugDescription)
        app.buttons["清除导入结果"].tap()
        XCTAssertTrue(app.staticTexts["本地文件验证"].waitForExistence(timeout: 10))
        app.buttons["管理与导入内容源"].tap()
        XCTAssertTrue(app.buttons["import-local-js"].waitForExistence(timeout: 10))
        app.buttons["import-local-js"].tap()
        try choose("Invalid.webox.js", app: app)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "下载到的是网页")).firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "local-import-visible-error"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["清除导入结果"].tap()
    }

    @MainActor private func choose(_ filename: String, app: XCUIApplication) throws {
        let files = app.collectionViews["File View"]
        let name = String(filename.dropLast(3))
        let file = files.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@ OR label BEGINSWITH %@", name, name)).firstMatch
        let container = files.cells["WeBox, Container"]
        if !file.exists {
            if !container.waitForExistence(timeout: 5) {
                let browse = app.tabBars.buttons["Browse"]
                XCTAssertTrue(browse.waitForExistence(timeout: 10), app.debugDescription)
                browse.tap()
                let local = app.cells["DOC.sidebar.item.On My iPhone"]
                if !local.exists { browse.tap() }
                XCTAssertTrue(local.waitForExistence(timeout: 10), app.debugDescription)
                local.tap()
            }
            XCTAssertTrue(container.waitForExistence(timeout: 15), app.debugDescription)
            tapThumbnail(container, in: files)
        }
        XCTAssertTrue(file.waitForExistence(timeout: 15), app.debugDescription)
        tapThumbnail(file, in: files)
        // The import actions open the single-selection picker, which dismisses
        // when a file is selected. Avoid querying a disappearing Open button.
    }

    @MainActor private func tapThumbnail(_ cell: XCUIElement, in files: XCUIElement) {
        if files.value as? String == "Icon Mode" {
            cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.24)).tap()
        } else {
            cell.tap()
        }
    }
}
