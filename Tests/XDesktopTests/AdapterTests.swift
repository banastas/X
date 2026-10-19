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

    func testLocalizedFollowingSortMenuIsClosedAtTheDeadline() async throws {
        try await load(); defer { close() }
        // A sort menu in another language: never recognized, but opened by the adapter's own click.
        try await change("""
            var following=document.querySelectorAll('[role=tab]')[1]; following.setAttribute('aria-expanded','false');
            following.addEventListener('click', () => {
              if (following.getAttribute('aria-selected') !== 'true') return;
              var existing=document.querySelector('[role=menu]');
              if (existing) { existing.remove(); following.setAttribute('aria-expanded','false'); return; }
              var menu=document.createElement('div'); menu.role='menu';
              for (var name of ['Populares','Recientes']) { var o=document.createElement('div'); o.role='menuitem'; o.textContent=name; menu.append(o); }
              document.body.append(menu); following.setAttribute('aria-expanded','true');
            });
            choose(1)
            """) { !$0.ready && $0.reason == "Selecting Recent for Following" }
        try await Task.sleep(for: .milliseconds(5500))
        let body = try await webView.evaluateJavaScript("window.__xDesktop.snapshot()", in: nil, contentWorld: WebsiteAdapter.world)
        XCTAssertEqual(WebsiteState.decode(body as Any)?.reason, "Could not select Recent; use the Following sort menu")
        let menuOpen = try await webView.evaluateJavaScript("!!document.querySelector('[role=menu]')") as? Bool
        XCTAssertEqual(menuOpen, false, "An open menu would hold automatic refresh back indefinitely")
        let after = try await webView.evaluateJavaScript("window.__xDesktop.snapshot()", in: nil, contentWorld: WebsiteAdapter.world)
        let closed = WebsiteState.decode(after as Any)
        XCTAssertEqual(closed?.ready, true)
        XCTAssertEqual(closed?.active, false)
    }
    func testFollowingRecentDefaultCanBeTurnedOff() async throws {
        try await load(); defer { close() }
        _ = try await webView.evaluateJavaScript("window.__xDesktop.setOptions({ followingRecent: false })", in: nil, contentWorld: WebsiteAdapter.world)
        try await change(followingSortFixture + "; choose(1)") { $0.ready && $0.selected == 1 && $0.reason.isEmpty }
        let sortClicks = try await webView.evaluateJavaScript("sortClicks") as? Int
        XCTAssertEqual(sortClicks, 0)
        let menuOpen = try await webView.evaluateJavaScript("!!document.querySelector('[role=menu]')") as? Bool
        XCTAssertEqual(menuOpen, false)
    }
    func testFeedRestorationRetriesUntilTabHandlersAttach() async throws {
        try await load(); defer { close() }
        // Swallow tab clicks for a moment, as X can render tabs before React hydrates them.
        _ = try await webView.evaluateJavaScript("var hydrated=false; setTimeout(() => hydrated=true, 1200); document.querySelector('[role=tablist]').addEventListener('click', e => { if (!hydrated) e.stopImmediatePropagation(); }, true); true")
        let e = expectation(description: "Following restored after hydration"); expected = { $0.ready && $0.selected == 1 }; pending = e
        _ = try await webView.evaluateJavaScript("window.__xDesktop.restoreFeed(1)", in: nil, contentWorld: WebsiteAdapter.world)
        await fulfillment(of: [e], timeout: 8)
        XCTAssertEqual(state?.restoreFailed, false)
        XCTAssertEqual(state?.feedChosen, false)
    }
    func testMenuFeedSelectionCountsAsTheReadersChoice() async throws {
        try await load(); defer { close() }
        let selected = try await webView.evaluateJavaScript("window.__xDesktop.selectFeed(1)", in: nil, contentWorld: WebsiteAdapter.world) as? Bool
        XCTAssertEqual(selected, true)
        try await change("void 0") { $0.ready && $0.selected == 1 && $0.feedChosen }
    }
    func testImageBeneathAPointIsFound() async throws {
        try await load(); defer { close() }
        _ = try await webView.evaluateJavaScript("var img=document.createElement('img'); img.src='https://pbs.twimg.com/media/TEST?format=jpg&name=small'; img.style.cssText='position:fixed;left:0;top:200px;width:100px;height:100px;opacity:0'; document.body.append(img); var cover=document.createElement('div'); cover.style.cssText='position:fixed;left:0;top:200px;width:100px;height:100px'; document.body.append(cover); true")
        let found = try await webView.evaluateJavaScript("window.__xDesktop.imageAt(50, 250)", in: nil, contentWorld: WebsiteAdapter.world) as? String
        XCTAssertEqual(found, "https://pbs.twimg.com/media/TEST?format=jpg&name=small")
        let none = try await webView.evaluateJavaScript("window.__xDesktop.imageAt(300, 600)", in: nil, contentWorld: WebsiteAdapter.world)
        XCTAssertNil(none as? String)
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
        // A pinned tab is not For you or Following, but it refreshes like them.
        try await change("document.querySelectorAll('[role=tab]')[0].setAttribute('aria-selected','false'); extra.setAttribute('aria-selected','true')") { !$0.recognized && $0.otherTab && $0.ready }
    }
    func testPaginationSpinnerDoesNotBlockAnAlreadyRenderedFeed() async throws {
        try await load(); defer { close() }
        _ = try await webView.evaluateJavaScript("var spinner=document.createElement('div'); spinner.role='progressbar'; spinner.textContent='Loading more'; document.querySelector('main').append(spinner)")
        let snapshot = try await webView.evaluateJavaScript("window.__xDesktop.snapshot()", in: nil, contentWorld: WebsiteAdapter.world)
        XCTAssertTrue(WebsiteState.decode(snapshot as Any)?.ready == true)
        try await change("document.querySelector('#feed').replaceChildren()") { !$0.ready }
    }
    /// Polls a page-world expression, since muting arrives in a media event after the call returns.
    private func waitFor(_ js: String) async throws {
        for _ in 0..<80 {
            if try await webView.evaluateJavaScript(js) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Page never satisfied \(js)")
    }
    func testUnrequestedSoundIsMutedAndDoesNotPauseRefresh() async throws {
        try await load(); defer { close() }
        _ = try await webView.evaluateJavaScript("var media=document.createElement('video'); media.src='silence.wav'; media.loop=true; document.body.append(media); media.play(); void 0")
        try await waitFor("media.muted && !media.paused")
        let snapshot = try await webView.evaluateJavaScript("window.__xDesktop.snapshot()", in: nil, contentWorld: WebsiteAdapter.world)
        XCTAssertEqual(WebsiteState.decode(snapshot as Any)?.protected, false)
        // A script unmuting a playing video, as X does when it remembers an earlier unmute.
        _ = try await webView.evaluateJavaScript("media.muted=false; void 0")
        try await waitFor("media.muted")
        _ = try await webView.evaluateJavaScript("var sound=document.createElement('audio'); sound.src='silence.wav'; sound.loop=true; document.body.append(sound); sound.play(); void 0")
        try await waitFor("sound.muted")
    }
    func testPressingThePlayerAllowsSound() async throws {
        try await load(); defer { close() }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderBack(nil)
        defer { window.close() }
        _ = try await webView.evaluateJavaScript("var player=document.createElement('div'); player.dataset.testid='videoPlayer'; player.style.cssText='position:fixed;left:0;top:0;width:200px;height:200px;z-index:9'; document.body.append(player); void 0")
        // A real click on the player, delivered to the web view rather than posted to the system.
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 600), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
            if type == .leftMouseDown { webView.mouseDown(with: event) } else { webView.mouseUp(with: event) }
        }
        // X mounts the video inside the player after the press.
        try await change("var media=document.createElement('video'); media.src='silence.wav'; media.loop=true; player.append(media); media.play(); void 0") { $0.protected }
        try await Task.sleep(for: .milliseconds(300))
        let muted = try await webView.evaluateJavaScript("media.muted") as? Bool
        XCTAssertEqual(muted, false)
        // The reader's player keeps its sound through X's own mute and unmute.
        _ = try await webView.evaluateJavaScript("media.muted=true; media.muted=false; void 0")
        try await Task.sleep(for: .milliseconds(300))
        let unmuted = try await webView.evaluateJavaScript("!media.muted && !media.paused") as? Bool
        XCTAssertEqual(unmuted, true)
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
    func testSignInReasonAndPinnedTabRefreshes() async throws {
        try await load(); defer { close() }
        try await change("document.documentElement.dataset.xDesktopFixture='signin'") { !$0.home && $0.reason == "Sign in to load your feeds" }
        try await change("document.documentElement.dataset.xDesktopFixture='true'; var extra=document.createElement('button'); extra.role='tab'; extra.textContent='List'; document.querySelector('[role=tablist]').append(extra); document.querySelectorAll('[role=tab]').forEach(tab => tab.setAttribute('aria-selected','false')); extra.setAttribute('aria-selected','true')") {
            $0.otherTab && $0.ready && $0.selected == -1 && $0.reason.isEmpty
        }
    }
    func testFeedErrorIsReported() async throws {
        try await load(); defer { close() }
        try await change("var error=document.createElement('div'); error.dataset.testid='error-detail'; error.textContent='Something went wrong'; document.querySelector('main').append(error)") { $0.failed && !$0.ready }
    }
    private func world(_ js: String) async throws -> Any? {
        try await webView.evaluateJavaScript(js, in: nil, contentWorld: WebsiteAdapter.world)
    }
    private func restorePlace(_ id: String, _ offset: Double) async throws -> String? {
        try await webView.callAsyncJavaScript("return await window.__xDesktop.restorePlace(id, offset)",
            arguments: ["id": id, "offset": offset], in: nil, contentWorld: WebsiteAdapter.world) as? String
    }

    func testPlaceIsTakenOnlyWhenScrolledDownAndComesBackAfterAReload() async throws {
        try await load(); defer { close() }
        let atTop = try await world("window.__xDesktop.snapshot(true).place") as? [String: Any]
        XCTAssertNil(atTop, "At the top of the feed there is no place to keep")
        _ = try await webView.evaluateJavaScript("window.scrollTo(0, 700); true")
        let place = try await world("window.__xDesktop.snapshot(true).place") as? [String: Any]
        let id = try XCTUnwrap(place?["id"] as? String)
        let offset = try XCTUnwrap((place?["offset"] as? NSNumber)?.doubleValue)
        XCTAssertTrue(id.hasPrefix("10"), id)
        let e = expectation(description: "Reloaded"); expected = { $0.ready && $0.feedTop }; pending = e
        webView.reload()
        await fulfillment(of: [e], timeout: 15)
        let outcome = try await restorePlace(id, offset)
        XCTAssertEqual(outcome, "restored")
        let top = try await webView.evaluateJavaScript(
            "[...document.querySelectorAll('article')].find(a => a.querySelector('a').getAttribute('href').endsWith('/\(id)')).getBoundingClientRect().top") as? Double
        XCTAssertEqual(top ?? .nan, offset, accuracy: 2)
        let marked = try await webView.evaluateJavaScript("[...document.body.children].some(e => e.textContent === 'You were here')") as? Bool
        XCTAssertEqual(marked, true)
    }

    func testAMissingPlaceReturnsToTheTop() async throws {
        try await load(); defer { close() }
        let outcome = try await restorePlace("999999", 120)
        XCTAssertEqual(outcome, "missing")
        let scrolled = try await webView.evaluateJavaScript("document.scrollingElement.scrollTop") as? Double
        XCTAssertEqual(scrolled, 0)
        let invalid = try await restorePlace("12; alert(1)", 0)
        XCTAssertEqual(invalid, "invalid")
    }

    func testOnlyXsOwnShowPostsButtonIsUsed() async throws {
        try await load(); defer { close() }
        _ = try await webView.evaluateJavaScript("var other=document.createElement('button'); other.textContent='Show more'; other.onclick=()=>document.body.dataset.wrong=1; document.querySelector('main').prepend(other); true")
        let none = try await world("window.__xDesktop.showNewPosts()") as? Bool
        XCTAssertEqual(none, false)
        _ = try await webView.evaluateJavaScript("var pill=document.createElement('div'); pill.role='button'; pill.textContent='Show 35 posts'; pill.onclick=()=>document.body.dataset.shown=1; document.querySelector('main').prepend(pill); true")
        let shown = try await world("window.__xDesktop.showNewPosts()") as? Bool
        XCTAssertEqual(shown, true)
        let clicked = try await webView.evaluateJavaScript("document.body.dataset.shown + '/' + document.body.dataset.wrong") as? String
        XCTAssertEqual(clicked, "1/undefined")
    }

    func testUnknownBridgeMessagesAreRejected() {
        XCTAssertNil(WebsiteState.decode(["home": true]))
        XCTAssertNil(WebsiteState.decode("bad"))
    }
}
