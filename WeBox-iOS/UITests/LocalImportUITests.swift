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
        try choose("Local-UTF16.webox.js", app: app)
        XCTAssertTrue(app.navigationBars["导入结果"].waitForExistence(timeout: 35), app.debugDescription)
        XCTAssertTrue(app.staticTexts["已添加到内容源"].exists, app.debugDescription)
        app.navigationBars["导入结果"].buttons["完成"].tap()
        XCTAssertTrue(app.staticTexts["本地文件验证"].waitForExistence(timeout: 10))
        app.buttons["管理与导入内容源"].tap()
        XCTAssertTrue(app.buttons["import-local-js"].waitForExistence(timeout: 10))
        app.buttons["import-local-js"].tap()
        try choose("Invalid.webox.js", app: app)
        XCTAssertTrue(app.navigationBars["导入结果"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "下载到的是网页")).firstMatch.exists, app.debugDescription)
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "local-import-visible-error"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.navigationBars["导入结果"].buttons["完成"].tap()
        app.buttons["import-local-js"].tap()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), app.debugDescription)
        cancel.tap()
        XCTAssertTrue(app.buttons["import-local-js"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["导入结果"].exists)
    }

    @MainActor private func choose(_ filename: String, app: XCUIApplication) throws {
        // Files may reopen the last directory. Otherwise navigate through local storage.
        if app.staticTexts[filename].waitForExistence(timeout: 3) { app.staticTexts[filename].firstMatch.tap(); finishSelection(app); return }
        let browse = app.tabBars.buttons["Browse"]
        if browse.waitForExistence(timeout: 5) { browse.tap(); browse.tap() }
        for name in ["On My iPhone", "WeBox", "ImportTests", filename] {
            let element = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
            if !element.waitForExistence(timeout: 10) {
                let image = XCTAttachment(screenshot: app.screenshot()); image.name = "picker-failure-" + name; image.lifetime = .keepAlways; add(image)
                XCTFail("Missing Files entry: \(name)\n\(app.debugDescription)"); return
            }
            element.tap()
        }
        finishSelection(app)
    }
    @MainActor private func finishSelection(_ app: XCUIApplication) {
        let open = app.buttons["Open"].firstMatch
        if open.waitForExistence(timeout: 2) { open.tap() }
        else if app.buttons["Import"].firstMatch.exists { app.buttons["Import"].firstMatch.tap() }
    }
}
