import XCTest
import WebKit
@testable import XDesktop

@MainActor
final class AdapterTests: XCTestCase, WKScriptMessageHandler {
    private var webView: WKWebView!
    private var state: WebsiteState?
    private var expected: ((WebsiteState) -> Bool)?
    private var pending: XCTestExpectation?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let state = WebsiteState.decode(message.body) else { return }
        self.state = state
        if expected?(state) == true { pending?.fulfill(); pending = nil; expected = nil }
    }

    private func load() async throws {
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(self, contentWorld: WebsiteAdapter.world, name: "websiteState")
        config.userContentController.addUserScript(WKUserScript(source: try WebsiteAdapter.script,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: WebsiteAdapter.world))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 460, height: 700), configuration: config)
        let fixture = Bundle.module.url(forResource: "home", withExtension: "html", subdirectory: "Fixtures")!
        let e = expectation(description: "Fixture timeline ready")
        expected = { $0.ready }; pending = e
        webView.loadFileURL(fixture, allowingReadAccessTo: fixture.deletingLastPathComponent())
        await fulfillment(of: [e], timeout: 15)
    }
    private func change(_ js: String, until predicate: @escaping (WebsiteState) -> Bool) async throws {
        let e = expectation(description: "Website state changed"); expected = predicate; pending = e
        _ = try await webView.evaluateJavaScript(js)
        await fulfillment(of: [e], timeout: 8)
    }
    private func close() {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "websiteState", contentWorld: WebsiteAdapter.world)
        webView.stopLoading(); webView = nil
    }
    func testRealWebKitDetectsReadyAndSwitchesFeeds() async throws {
        try await load(); defer { close() }
        XCTAssertEqual(state?.selected, 0)
        try await change("document.querySelectorAll('[role=tab]')[1].click()") { $0.ready && $0.selected == 1 }
    }
    func testDraftRemainsProtectedAfterBlur() async throws {
        try await load(); defer { close() }
        try await change("fixture.draft()") { $0.protected }
        _ = try await webView.evaluateJavaScript("fixture.blur()")
        _ = try await webView.evaluateJavaScript("window.__xDesktop.refreshState()", in: nil, contentWorld: WebsiteAdapter.world)
        XCTAssertTrue(state?.protected == true)
        try await change("fixture.clearDraft()") { !$0.protected }
    }
    func testModalAndUnknownMarkupFailClosed() async throws {
        try await load(); defer { close() }
        try await change("fixture.dialog()") { $0.protected }
        try await change("document.querySelector('[role=tablist]').remove()") { !$0.recognized && !$0.ready }
    }
    func testFeedRestorationUsesActualTabControl() async throws {
        try await load(); defer { close() }
        let e = expectation(description: "Following restored"); expected = { $0.ready && $0.selected == 1 }; pending = e
        _ = try await webView.evaluateJavaScript("window.__xDesktop.restoreFeed(1)", in: nil, contentWorld: WebsiteAdapter.world)
        await fulfillment(of: [e], timeout: 8)
    }
    func testPlayingMediaProtectsEvenWithoutFocus() async throws {
        try await load(); defer { close() }
        try await change("var media = document.createElement('audio'); media.src='silence.wav'; media.muted=true; media.loop=true; document.body.append(media); media.play(); void 0") { $0.protected && $0.reason == "Media playing" }
    }
    func testScrollBoundaryTracksDocumentAndNestedContainers() async throws {
        try await load(); defer { close() }
        XCTAssertTrue(state?.atTop == true)
        try await change("window.scrollTo(0, 300)") { !$0.atTop }
        try await change("window.scrollTo(0, 0)") { $0.atTop }
        try await change("fixture.nested(); var rect=document.querySelector('#nested').getBoundingClientRect(); document.dispatchEvent(new PointerEvent('pointermove', {clientX:rect.x+30, clientY:rect.y+30}))") { !$0.atTop }
        try await change("document.querySelector('#nested').scrollTop=0") { $0.atTop }
    }
    func testMediaPauseAllowsRefreshAgain() async throws {
        try await load(); defer { close() }
        try await change("var media=document.createElement('audio'); media.src='silence.wav'; media.muted=true; media.loop=true; document.body.append(media); media.play(); void 0") { $0.protected }
        try await change("media.pause()") { !$0.protected && $0.ready }
    }
    func testPageCannotAccessIsolatedAdapter() async throws {
        try await load(); defer { close() }
        let value = try await webView.evaluateJavaScript("typeof window.__xDesktop") as? String
        XCTAssertEqual(value, "undefined")
    }
    func testExtraPinnedTabsAndMediaTablistsDoNotBreakHomeDetection() async throws {
        try await load(); defer { close() }
        _ = try await webView.evaluateJavaScript("var extra=document.createElement('button'); extra.role='tab'; extra.setAttribute('aria-selected','false'); extra.textContent='Projects'; document.querySelector('[role=tablist]').append(extra); var mediaTabs=document.createElement('div'); mediaTabs.role='tablist'; mediaTabs.innerHTML='<button role=tab>Image</button>'; document.querySelector('main').append(mediaTabs)")
        let snapshot = try await webView.evaluateJavaScript("window.__xDesktop.snapshot()", in: nil, contentWorld: WebsiteAdapter.world)
        XCTAssertTrue(WebsiteState.decode(snapshot as Any)?.ready == true)
        try await change("document.querySelectorAll('[role=tab]')[0].setAttribute('aria-selected','false'); extra.setAttribute('aria-selected','true')") { !$0.recognized && !$0.ready }
    }
    func testPaginationSpinnerDoesNotBlockAnAlreadyRenderedFeed() async throws {
        try await load(); defer { close() }
        _ = try await webView.evaluateJavaScript("var spinner=document.createElement('div'); spinner.role='progressbar'; spinner.textContent='Loading more'; document.querySelector('main').append(spinner)")
        let snapshot = try await webView.evaluateJavaScript("window.__xDesktop.snapshot()", in: nil, contentWorld: WebsiteAdapter.world)
        XCTAssertTrue(WebsiteState.decode(snapshot as Any)?.ready == true)
        try await change("document.querySelector('#feed').replaceChildren()") { !$0.ready }
    }
    func testMutingAutoplayVideoResumesRefresh() async throws {
        try await load(); defer { close() }
        try await change("var media=document.createElement('video'); media.src='silence.wav'; media.loop=true; document.body.append(media); media.play(); void 0") { $0.protected }
        try await change("media.muted=true") { !$0.protected && $0.ready }
        try await change("media.muted=false") { $0.protected }
    }
    func testUnknownBridgeMessagesAreRejected() {
        XCTAssertNil(WebsiteState.decode(["home": true]))
        XCTAssertNil(WebsiteState.decode("bad"))
    }
}
