import AppKit
import XCTest
import WebKit
@testable import XDesktop

// Native event inputs delivered directly to the production event handler. These
// never post system events or interact with the user's authenticated session.
private final class WheelEvent: NSEvent {
    var targetWindow: NSWindow?
    var precise = false
    var vertical: CGFloat = 2
    var horizontal: CGFloat = 0
    var momentum: NSEvent.Phase = []
    override var window: NSWindow? { targetWindow }
    override var locationInWindow: NSPoint { NSPoint(x: 230, y: 350) }
    override var phase: NSEvent.Phase { [] }
    override var momentumPhase: NSEvent.Phase { momentum }
    override var hasPreciseScrollingDeltas: Bool { precise }
    override var scrollingDeltaY: CGFloat { vertical }
    override var scrollingDeltaX: CGFloat { horizontal }
}

@MainActor
final class WheelRefreshTests: XCTestCase {
    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<150 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Wheel refresh did not reach the expected state")
    }

    private func withFixture(_ check: (BrowserModel, NSWindow) async throws -> Void) async throws {
        _ = NSApplication.shared
        let domain = "as.banast.xdesktop.wheel-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defaults.set(false, forKey: "autoRefresh")
        defaults.set(1, forKey: "selectedFeed")
        let fixture = Bundle.module.url(forResource: "home", withExtension: "html", subdirectory: "Fixtures")!
        let model = BrowserModel(defaults: defaults, fixtureURL: fixture)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "X wheel test fixture"
        window.contentView = model.webView
        window.orderBack(nil)
        model.attach(to: window)
        defer { model.shutdown(); model.webView.stopLoading(); window.close(); defaults.removePersistentDomain(forName: domain) }
        try await waitUntil { !model.loading && model.page.ready && model.page.atTop }
        try await check(model, window)
    }

    func testCoarseAndPreciseWheelsReloadOnceAndKeepFollowingWhilePaused() async throws {
        try await withFixture { model, window in
            for precise in [false, true] {
                let previous = model.lastRefresh
                let event = WheelEvent(); event.targetWindow = window; event.precise = precise
                event.vertical = precise ? 32 : 2
                model.handleScroll(event)
                XCTAssertEqual(model.pullDistance, 32)
                XCTAssertFalse(model.pullArmed)
                model.handleScroll(event); model.handleScroll(event)
                XCTAssertTrue(model.pullArmed)
                XCTAssertTrue(model.pullUsesWheel)
                XCTAssertEqual(model.lastRefresh, previous, "A wheel pull must wait for release")
                try await waitUntil { model.lastRefresh != previous && !model.loading }
                XCTAssertEqual(model.page.selected, 1)
                XCTAssertFalse(model.autoRefresh)
                let completed = model.lastRefresh
                try await Task.sleep(for: .milliseconds(800))
                XCTAssertEqual(model.lastRefresh, completed, "One burst must produce only one reload")
                XCTAssertEqual(model.pullDistance, 0)
            }
        }
    }

    func testWheelCancellationAndMomentumDoNotReload() async throws {
        try await withFixture { model, window in
            let previous = model.lastRefresh
            let event = WheelEvent(); event.targetWindow = window; event.vertical = 6
            model.handleScroll(event)
            XCTAssertTrue(model.pullArmed)
            model.cancelGesture()
            try await Task.sleep(for: .milliseconds(800))
            XCTAssertEqual(model.lastRefresh, previous)
            event.momentum = .changed
            model.handleScroll(event)
            XCTAssertFalse(model.pullArmed)
            try await Task.sleep(for: .milliseconds(800))
            XCTAssertEqual(model.lastRefresh, previous)
        }
    }

    func testFreshRendererStateBlocksReloadAfterScrollOrDraft() async throws {
        try await withFixture { model, window in
            let event = WheelEvent(); event.targetWindow = window; event.vertical = 6
            for js in ["window.scrollTo(0, 300)", "fixture.draft()"] {
                let previous = model.lastRefresh
                model.handleScroll(event)
                XCTAssertTrue(model.pullArmed)
                _ = try await model.webView.evaluateJavaScript(js)
                try await Task.sleep(for: .milliseconds(900))
                XCTAssertEqual(model.lastRefresh, previous)
                _ = try await model.webView.evaluateJavaScript("fixture.clearDraft(); window.scrollTo(0,0)")
                try await waitUntil { model.page.atTop && !model.page.protected }
            }
        }
    }
}
