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
    private let followingSortFixture = """
        var following=document.querySelectorAll('[role=tab]')[1];
        following.setAttribute('aria-expanded','false');
        var sort='Popular', sortClicks=0, selectedBeforeClick=false;
        following.addEventListener('click', () => {
          selectedBeforeClick=following.getAttribute('aria-selected') === 'true';
        }, true);
        following.addEventListener('click', () => {
          if (!selectedBeforeClick) return;
          var existing=document.querySelector('[role=menu]');
          if (existing) { existing.remove(); following.setAttribute('aria-expanded','false'); return; }
          var menu=document.createElement('div'); menu.role='menu';
          for (var name of ['Popular','Recent']) {
            let option=document.createElement('div'); option.role='menuitem'; option.textContent=name;
            option.setAttribute('aria-selected', String(sort === name));
            option.addEventListener('click', () => {
              sort=option.textContent; sortClicks++; menu.remove();
              following.setAttribute('aria-expanded','false');
              document.querySelector('#feed').dataset.sort=sort;
            });
            menu.append(option);
          }
          document.body.append(menu); following.setAttribute('aria-expanded','true');
        });
        """

    func testFollowingDefaultsToRecentAfterEveryDocumentLoad() async throws {
        try await load(); defer { close() }
        for attempt in 0..<2 {
            if attempt > 0 {
                let e = expectation(description: "Reload ready"); expected = { $0.ready && $0.selected == 0 }; pending = e
                webView.reload()
                await fulfillment(of: [e], timeout: 15)
            }
            try await change(followingSortFixture + "; following.click()") {
                $0.ready && $0.selected == 1 && $0.reason.isEmpty
            }
            let valueString = try await webView.evaluateJavaScript("sort") as? String
            XCTAssertEqual(valueString, "Recent")
            let sortClicks = try await webView.evaluateJavaScript("sortClicks") as? Int
            XCTAssertEqual(sortClicks, 1)
        }
    }

    func testFollowingSortRetriesAfterLateControlHydration() async throws {
        try await load(); defer { close() }
        let delayed = followingSortFixture + """
            var original=following, placeholder=following.cloneNode(true);
            following.replaceWith(placeholder);
            setTimeout(() => placeholder.replaceWith(original), 1200);
            """
        try await change("choose(1); setTimeout(() => { " + delayed + " }, 700)") {
            !$0.ready && $0.reason == "Selecting Recent for Following"
        }
        try await change("void 0") { $0.ready && $0.selected == 1 && $0.reason.isEmpty }
        let sort = try await webView.evaluateJavaScript("document.querySelector('#feed').dataset.sort") as? String
        XCTAssertEqual(sort, "Recent")
    }

    func testFollowingDefaultDoesNotOverrideLaterManualSortChoice() async throws {
        try await load(); defer { close() }
        try await change(followingSortFixture + "; following.click()") { $0.ready && $0.selected == 1 }
        _ = try await webView.evaluateJavaScript("sort='Popular'; document.querySelector('#feed').dataset.sort=sort; true")
        _ = try await webView.evaluateJavaScript("window.__xDesktop.snapshot()", in: nil, contentWorld: WebsiteAdapter.world)
        let valueString = try await webView.evaluateJavaScript("sort") as? String
        XCTAssertEqual(valueString, "Popular")
        let sortClicks = try await webView.evaluateJavaScript("sortClicks") as? Int
        XCTAssertEqual(sortClicks, 1)
    }

    func testFollowingSortWaitsForDraftAndExistingMenu() async throws {
        try await load(); defer { close() }
        try await change(followingSortFixture + "; fixture.draft(); following.click(); document.querySelector('[role=menu]')?.remove(); following.setAttribute('aria-expanded','false')") {
            $0.selected == 1 && $0.draft
        }
        let sortClicks = try await webView.evaluateJavaScript("sortClicks") as? Int
        XCTAssertEqual(sortClicks, 0)
        try await change("var menu=document.createElement('div'); menu.role='menu'; menu.textContent='Unrelated'; document.body.append(menu); fixture.clearDraft()") { $0.active && !$0.draft }
        let clicksWhileMenuOpen = try await webView.evaluateJavaScript("sortClicks") as? Int
        XCTAssertEqual(clicksWhileMenuOpen, 0)
        try await change("menu.remove()") { $0.ready && $0.selected == 1 && !$0.active }
        let valueString = try await webView.evaluateJavaScript("sort") as? String
        XCTAssertEqual(valueString, "Recent")
    }

    func testUnrecognizedFollowingSortMenuDoesNotClickUnrelatedActions() async throws {
        try await load(); defer { close() }
        try await change("var following=document.querySelectorAll('[role=tab]')[1]; following.setAttribute('aria-expanded','false'); following.addEventListener('click', () => { if(document.querySelector('[role=menu]')) return; var menu=document.createElement('div'); menu.role='menu'; menu.innerHTML='<button onclick=\"document.body.dataset.clicked=true\">Recent</button>'; document.body.append(menu) }); choose(1)") {
            !$0.ready && $0.reason == "Selecting Recent for Following"
        }
        // Offscreen WebKit fixtures can throttle heartbeat timers. Query directly
        // after the deadline, as the native app does before a refresh.
        try await Task.sleep(for: .milliseconds(5500))
        let body = try await webView.evaluateJavaScript("window.__xDesktop.snapshot()", in: nil, contentWorld: WebsiteAdapter.world)
        let snapshot = WebsiteState.decode(body as Any)
        XCTAssertTrue(snapshot?.ready == true)
        XCTAssertEqual(snapshot?.reason, "Could not select Recent; use the Following sort menu")
        let clicked = try await webView.evaluateJavaScript("document.body.dataset.clicked") as? String
        XCTAssertNil(clicked)
    }

    func testPlayingMediaProtectsEvenWithoutFocus() async throws {
        try await load(); defer { close() }
        try await change("var media = document.createElement('audio'); media.src='silence.wav'; media.muted=true; media.loop=true; document.body.append(media); media.play(); void 0") { $0.protected && $0.reason == "Auto-refresh paused while media plays" }
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
    func testReadingPositionAndInteractionAreReported() async throws {
        try await load(); defer { close() }
        XCTAssertTrue(state?.feedTop == true)
        try await change("window.scrollTo(0, 300)") { !$0.feedTop && $0.active }
        try await change("window.scrollTo(0, 0)") { $0.feedTop }
        try await change("void 0") { !$0.active }
        try await change("var menu=document.createElement('div'); menu.role='menu'; menu.textContent='Menu'; document.body.append(menu)") { $0.active }
        try await change("menu.remove()") { !$0.active }
    }
    func testDraftIsDistinctFromAFocusedEmptyComposer() async throws {
        try await load(); defer { close() }
        try await change("fixture.draft('')") { $0.protected && !$0.draft }
        try await change("document.querySelector('textarea').value='Hello'; document.querySelector('textarea').dispatchEvent(new Event('input', {bubbles: true}))") { $0.draft }
        try await change("fixture.clearDraft()") { !$0.draft && !$0.protected }
    }
    func testSignInAndPinnedTabReasons() async throws {
        try await load(); defer { close() }
        try await change("document.documentElement.dataset.xDesktopFixture='signin'") { !$0.home && $0.reason == "Sign in to load your feeds" }
        try await change("document.documentElement.dataset.xDesktopFixture='true'; var extra=document.createElement('button'); extra.role='tab'; extra.textContent='List'; document.querySelector('[role=tablist]').append(extra); document.querySelectorAll('[role=tab]').forEach(tab => tab.setAttribute('aria-selected','false')); extra.setAttribute('aria-selected','true')") {
            $0.otherTab && !$0.ready && $0.reason == "Auto-refresh covers For you and Following only"
        }
    }
    func testFeedErrorIsReported() async throws {
        try await load(); defer { close() }
        try await change("var error=document.createElement('div'); error.dataset.testid='error-detail'; error.textContent='Something went wrong'; document.querySelector('main').append(error)") { $0.failed && !$0.ready }
    }
    func testUnknownBridgeMessagesAreRejected() {
        XCTAssertNil(WebsiteState.decode(["home": true]))
        XCTAssertNil(WebsiteState.decode("bad"))
    }
}
