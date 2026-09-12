import XCTest
import WebKit
@testable import XDesktop

@MainActor
final class BrowserModelTests: XCTestCase {
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<150 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Browser model did not reach the expected state within 15 seconds")
    }
    func testModelReloadsFiveTimesAndRestoresFollowing() async throws {
        let domain = "as.banast.xdesktop.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        let fixture = Bundle.module.url(forResource: "home", withExtension: "html", subdirectory: "Fixtures")!
        defaults.set(1, forKey: "selectedFeed")
        let model = BrowserModel(defaults: defaults, fixtureURL: fixture)
        defer { model.shutdown(); defaults.removePersistentDomain(forName: domain) }
        model.home()
        try await waitUntil { !model.loading && model.page.ready }
        XCTAssertEqual(model.page.selected, 1)
        model.toggleAutomatic()
        XCTAssertFalse(model.autoRefresh)
        for _ in 0..<5 {
            let previous = model.lastRefresh
            model.refresh()
            try await waitUntil { model.lastRefresh != previous && !model.loading }
            XCTAssertEqual(model.page.selected, 1)
            XCTAssertNil(model.errorMessage)
            XCTAssertFalse(model.autoRefresh)
        }
        XCTAssertEqual(defaults.integer(forKey: "selectedFeed"), 1)
    }
    func testBackFromSPARouteCompletesWithoutAFullDocumentLoad() async throws {
        let domain = "as.banast.xdesktop.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        let fixture = Bundle.module.url(forResource: "home", withExtension: "html", subdirectory: "Fixtures")!
        let model = BrowserModel(defaults: defaults, fixtureURL: fixture)
        defer { model.shutdown(); defaults.removePersistentDomain(forName: domain) }
        model.home()
        try await waitUntil { !model.loading && model.page.ready }
        _ = try await model.webView.evaluateJavaScript("history.pushState(null, '', '#detail'); document.documentElement.dataset.xDesktopFixture='false'; true")
        try await waitUntil { !model.page.home }
        XCTAssertTrue(model.webView.canGoBack)
        model.back()
        try await waitUntil { !model.loading && model.page.ready }
        XCTAssertNil(model.errorMessage)
    }
    func testReloadWorksForForYouAndPauseSurvivesNewModel() async throws {
        let domain = "as.banast.xdesktop.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        let fixture = Bundle.module.url(forResource: "home", withExtension: "html", subdirectory: "Fixtures")!
        defaults.set(false, forKey: "autoRefresh")
        defaults.set(0, forKey: "selectedFeed")
        let model = BrowserModel(defaults: defaults, fixtureURL: fixture)
        defer { model.shutdown(); defaults.removePersistentDomain(forName: domain) }
        model.home()
        try await waitUntil { !model.loading && model.page.ready }
        for _ in 0..<5 {
            let previous = model.lastRefresh
            model.refresh()
            try await waitUntil { model.lastRefresh != previous && !model.loading }
            XCTAssertEqual(model.page.selected, 0)
        }
        let reopened = BrowserModel(defaults: defaults, fixtureURL: fixture)
        XCTAssertFalse(reopened.autoRefresh)
        reopened.shutdown()
    }
}
