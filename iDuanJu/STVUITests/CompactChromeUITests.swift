import XCTest

/// Native orientation + viewport regression. Colour-bar fixture is labelled, not a real source.
final class CompactChromeUITests: XCTestCase {
    func testCompactOverlayDoesNotResizeVideo() {
        continueAfterFailure = false
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launchEnvironment = ["STV_ROUTE": "fxplay:/player_landscape.mp4", "STV_KEEP_CHROME": "1"]
        app.launch()
        let video = app.descendants(matching: .any)["player.renderSurface"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 20))
        // Landscape app.screenshot() is cropped/rotated on the current simulator runtime. Visual evidence is
        // captured from the actual display with simctl at the RAW_* checkpoints, not from that snapshot API.
        for landscape in [false, true] {
            XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
            sleep(3)
            XCTAssertEqual(app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height, landscape)
            let frame = video.value as? String
            XCTAssertNotEqual(frame, "unmounted")
            XCTAssertTrue(frame?.contains("renderLayer") == true, "Must measure the engine render layer")
            print("RENDER_\(landscape ? "LANDSCAPE" : "PORTRAIT")_EXPANDED \(frame ?? "nil")")
            print(landscape ? "RAW_LANDSCAPE_EXPANDED" : "RAW_PORTRAIT_EXPANDED"); sleep(5)
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)).tap()
            sleep(1)
            XCTAssertTrue(app.staticTexts["player.compactTitle"].exists)
            XCTAssertEqual(frame, video.value as? String, "Chrome must overlay, never resize the actual render layer")
            print("RENDER_\(landscape ? "LANDSCAPE" : "PORTRAIT")_COMPACT \(video.value as? String ?? "nil")")
            print(landscape ? "RAW_LANDSCAPE_COMPACT" : "RAW_PORTRAIT_COMPACT"); sleep(5)
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.45)).tap()
            sleep(1)
            XCTAssertEqual(frame, video.value as? String, "Second expanded state must retain the actual surface bounds")
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
