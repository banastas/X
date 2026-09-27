import AppKit
import Combine
import XCTest
import WebKit
@testable import XDesktop

/// Navigation recovery, status, and resource behavior of the browser model against local fixtures.
@MainActor
final class RecoveryTests: XCTestCase {
    private var fixture: URL { Bundle.module.url(forResource: "home", withExtension: "html", subdirectory: "Fixtures")! }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<150 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Browser model did not reach the expected state within 15 seconds")
    }

    private func withModel(_ url: URL? = nil, attached: Bool = false, configure: (BrowserModel) -> Void = { _ in },
                           _ check: @MainActor (BrowserModel, UserDefaults) async throws -> Void) async throws {
        _ = NSApplication.shared
        let domain = "as.banast.xdesktop.recovery-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.set(false, forKey: "autoRefresh")
        let model = BrowserModel(defaults: defaults, fixtureURL: url ?? fixture, windowVisible: { $0.isVisible })
        configure(model)
        var window: NSWindow?
        if attached {
            let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
            host.isReleasedWhenClosed = false
            host.title = "X recovery test fixture"
            host.contentView = model.webView
            host.orderBack(nil)
            model.attach(to: host)
            window = host
        } else {
            model.home()
        }
        defer { model.shutdown(); model.webView.stopLoading(); window?.close(); defaults.removePersistentDomain(forName: domain) }
        try await check(model, defaults)
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("xdesktop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    func testBackBetweenNonHomeRoutesSettlesWithoutAFullLoad() async throws {
        try await withModel(attached: true) { model, _ in
            try await waitUntil { !model.loading && model.page.ready }
            _ = try await model.webView.evaluateJavaScript("history.pushState(null, '', '#detail'); document.documentElement.dataset.xDesktopFixture='false'; history.pushState(null, '', '#detail2'); true")
            try await waitUntil { !model.page.home }
            model.back()
            XCTAssertTrue(model.loading)
            try await waitUntil { !model.loading && model.page.reason == "Open Home to auto-refresh" }
            XCTAssertEqual(model.webView.url?.fragment, "detail")
            XCTAssertFalse(model.page.home)
            XCTAssertNil(model.errorMessage)
        }
    }

    func testRetryAfterFailedFirstLoadLoadsHome() async throws {
        let target = try temporaryFolder().appendingPathComponent("home.html")
        try await withModel(target) { model, _ in
            try await waitUntil { model.errorMessage != nil }
            XCTAssertNil(model.webView.url, "A failed first load leaves nothing committed to reload")
            try FileManager.default.copyItem(at: fixture, to: target)
            model.refresh()
            try await waitUntil { !model.loading && model.page.ready }
            XCTAssertNil(model.errorMessage)
        }
    }

    func testLoadTimeoutRetriesUnlessTheFeedIsUnrecognized() async throws {
        let folder = try temporaryFolder()
        let cases = [("<!doctype html><title>Stalled</title><main></main>", false),
                     ("<!doctype html><html data-x-desktop-fixture=\"true\"><main data-testid=\"primaryColumn\"></main></html>", true)]
        for (html, manual) in cases {
            let target = folder.appendingPathComponent(UUID().uuidString).appendingPathComponent("home.html")
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try html.write(to: target, atomically: true, encoding: .utf8)
            try await withModel(target, attached: true, configure: { $0.loadTimeout = 1.5 }) { model, _ in
                try await waitUntil { model.errorMessage != nil }
                XCTAssertFalse(model.loading)
                XCTAssertEqual(model.schedule.manualRetryRequired, manual)
                XCTAssertEqual(model.schedule.retryAt != nil, !manual)
            }
        }
    }

    func testScriptRedirectAwayFromXOffersBrowser() async throws {
        try await withModel { model, _ in
            try await waitUntil { !model.loading && model.page.ready }
            _ = try await model.webView.evaluateJavaScript("location.href = 'https://example.invalid/path'; true")
            try await waitUntil { model.notice != nil }
            XCTAssertEqual(model.notice?.action, .openInBrowser(URL(string: "https://example.invalid/path")!))
            XCTAssertEqual(model.status, "Blocked a redirect to example.invalid.")
            XCTAssertTrue(model.page.ready, "The current page stays in place")
        }
    }

    func testSignInPageExplainsWhatToDo() async throws {
        try await withModel { model, _ in
            try await waitUntil { !model.loading && model.page.ready }
            model.toggleAutomatic()
            _ = try await model.webView.evaluateJavaScript("document.documentElement.dataset.xDesktopFixture='signin'; true")
            try await waitUntil { model.status == "Sign in to load your feeds" }
        }
    }

    func testDraftBlocksSwipeNavigationUntilResolved() async throws {
        try await withModel { model, _ in
            try await waitUntil { !model.loading && model.page.ready }
            XCTAssertTrue(model.webView.allowsBackForwardNavigationGestures)
            _ = try await model.webView.evaluateJavaScript("fixture.draft(); true")
            try await waitUntil { model.page.draft }
            XCTAssertFalse(model.webView.allowsBackForwardNavigationGestures)
            _ = try await model.webView.evaluateJavaScript("fixture.clearDraft(); true")
            try await waitUntil { !model.page.draft }
            XCTAssertTrue(model.webView.allowsBackForwardNavigationGestures)
        }
    }

    func testPinnedTabIsNotOverriddenByFeedRestoration() async throws {
        try await withModel { model, defaults in
            try await waitUntil { !model.loading && model.page.ready }
            XCTAssertEqual(defaults.object(forKey: "selectedFeed") as? Int, 0)
            _ = try await model.webView.evaluateJavaScript("var extra=document.createElement('button'); extra.role='tab'; extra.textContent='List'; document.querySelector('[role=tablist]').append(extra); document.querySelectorAll('[role=tab]').forEach(tab => tab.setAttribute('aria-selected','false')); extra.setAttribute('aria-selected','true'); true")
            try await waitUntil { model.page.otherTab }
            XCTAssertNil(defaults.object(forKey: "selectedFeed"))
            XCTAssertEqual(model.page.reason, "Auto-refresh covers For you and Following only")
        }
    }

    func testZoomStepsPersist() async throws {
        try await withModel { model, defaults in
            model.zoomIn(); model.zoomIn()
            XCTAssertEqual(model.pageZoom, 1.25)
            XCTAssertEqual(model.webView.pageZoom, 1.25)
            model.zoomOut(); model.zoomOut(); model.zoomOut()
            XCTAssertEqual(model.pageZoom, 0.9)
            let reopened = BrowserModel(defaults: defaults, fixtureURL: fixture)
            XCTAssertEqual(reopened.webView.pageZoom, 0.9)
            reopened.shutdown()
            model.resetZoom()
            XCTAssertEqual(defaults.double(forKey: "pageZoom"), 1)
        }
    }

    func testIdleModelDoesNotInvalidateTheInterface() async throws {
        try await withModel(attached: true) { model, _ in
            try await waitUntil { !model.loading && model.page.ready }
            try await Task.sleep(for: .seconds(1))
            var changes = 0
            let subscription = model.objectWillChange.sink { changes += 1 }
            try await Task.sleep(for: .seconds(3))
            subscription.cancel()
            XCTAssertLessThan(changes, 3, "An idle window should not republish unchanged state")
        }
    }
}
