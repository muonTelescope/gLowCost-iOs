import XCTest

final class TabNavigationTests: XCTestCase {
    func testCustomTabs() { checkNavigation(system: false) }
    func testSystemTabs() { checkNavigation(system: true) }

    private func checkNavigation(system: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "-useSystemTabBar", system ? "YES" : "NO"]
        app.launch()
        func tab(_ name: String) -> XCUIElement {
            system ? app.tabBars.buttons[name] : app.buttons["tab-" + name.lowercased()]
        }
        XCTAssertTrue(tab("Now").waitForExistence(timeout: 10))
        tab("Now").tap()
        XCTAssertTrue(app.otherElements["logging-status"].waitForExistence(timeout: 5))
        for name in ["Runs", "Detector", "Settings"] {
            tab(name).tap()
            XCTAssertFalse(app.otherElements["logging-status"].exists, "Logging must only be on Now")
        }
        let top = app.buttons["Leave the demo"]
        XCTAssertTrue(top.isHittable)
        for _ in 0..<5 { app.swipeUp() }
        let bottom = app.buttons["Forget MuonP4"]
        XCTAssertTrue(bottom.exists)
        XCTAssertLessThan(bottom.frame.maxY, tab("Settings").frame.minY, "Bottom control must clear the tab bar")
        XCTAssertFalse(top.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = system ? "System bottom clearance" : "Custom bottom clearance"; shot.lifetime = .keepAlways; add(shot)
        tab("Settings").tap()
        let returned = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: top)
        wait(for: [returned], timeout: 5)
        tab("Now").tap()
        XCTAssertTrue(app.otherElements["logging-status"].exists)
        let nowShot = XCTAttachment(screenshot: app.screenshot()); nowShot.name = "Now logging status"; nowShot.lifetime = .keepAlways; add(nowShot)
    }
}
