import AppKit
import Combine
import WebKit
import XCore

/// A transient status-strip message, optionally with one follow-up action.
struct Notice: Equatable {
    enum Action: Equatable {
        case openInBrowser(URL)
        case revealInFinder(URL)
        var title: String {
            switch self {
            case .openInBrowser: "Open in Browser"
            case .revealInFinder: "Show in Finder"
            }
        }
    }
    let message: String
    let action: Action?
    let expires: Double
}

@MainActor
final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    @Published private(set) var status = "Loading X"
    @Published private(set) var loading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var autoRefresh: Bool
    @Published private(set) var pullDistance: Double = 0
    @Published private(set) var pullArmed = false
    @Published private(set) var pullUsesWheel = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var notice: Notice?
    @Published private(set) var pageZoom: Double
    /// False until the first document shows something, so launch never flashes an empty white view.
    @Published private(set) var hasContent = false
    let webView: WKWebView
    private(set) var page = WebsiteState.empty
    private(set) var schedule: RefreshSchedule
    /// Seconds a navigation may take to reach a ready state before it is treated as failed.
    var loadTimeout: Double = 45
    static let zoomLevels: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]
    private var pull = PullGesture()
    private let defaults: UserDefaults
    private let fixtureURL: URL?
    private let windowVisible: @MainActor (NSWindow) -> Bool
    private var timer: Timer?
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var environmentPaused = Set<String>()
    private var documentLoaded = false
    private var checkingRefresh = false
    private var loadStarted: Double?
    private var restoreFeed: Int?
    private var feedFailed = false
    private var lastCrash: Double?
    private var focusedWebView = false
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    private var popupWindows: [NSWindow] = []
    private var popupDelegates: [PopupDelegate] = []
    private weak var mainWindow: NSWindow?
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    /// A window on another Space, fully covered, or behind the lock screen is not visible,
    /// even though AppKit still reports `isVisible`.
    private var foregroundAvailable: Bool {
        guard environmentPaused.isEmpty, let mainWindow else { return false }
        return mainWindow.isVisible && !mainWindow.isMiniaturized && windowVisible(mainWindow)
    }
    var pullEligible: Bool {
        foregroundAvailable && page.home && page.ready && !page.protected && !schedule.loading && errorMessage == nil
    }
    var canZoomIn: Bool { pageZoom < Self.zoomLevels.last! }
    var canZoomOut: Bool { pageZoom > Self.zoomLevels.first! }

    init(defaults: UserDefaults = .standard, fixtureURL: URL? = nil,
         windowVisible: @escaping @MainActor (NSWindow) -> Bool = { $0.occlusionState.contains(.visible) }) {
        self.defaults = defaults
        self.fixtureURL = fixtureURL
        self.windowVisible = windowVisible
        defaults.register(defaults: ["autoRefresh": true, "pageZoom": 1.0])
        autoRefresh = defaults.bool(forKey: "autoRefresh")
        schedule = RefreshSchedule(enabled: defaults.bool(forKey: "autoRefresh"))
        pageZoom = min(max(defaults.double(forKey: "pageZoom"), Self.zoomLevels.first!), Self.zoomLevels.last!)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = fixtureURL == nil ? .default() : .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // X's player uses the element Fullscreen API, which WKWebView leaves off by default.
        configuration.preferences.isElementFullscreenEnabled = true
        webView = XWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.pageZoom = pageZoom
        webView.isInspectable = _isDebugAssertConfiguration()
        // Keep the normal WebKit user agent. Do not disguise the browser.
        do {
            configuration.userContentController.add(self, contentWorld: WebsiteAdapter.world, name: "websiteState")
            configuration.userContentController.addUserScript(WKUserScript(
                source: try WebsiteAdapter.script, injectionTime: .atDocumentEnd,
                forMainFrameOnly: true, in: WebsiteAdapter.world))
        } catch {
            errorMessage = "The website adapter is missing. Rebuild the application."
        }
    }

    func attach(to window: NSWindow) {
        mainWindow = window
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observeWorkspace(NSWorkspace.willSleepNotification, key: "sleep", paused: true)
        observeWorkspace(NSWorkspace.didWakeNotification, key: "sleep", paused: false)
        observeWorkspace(NSWorkspace.sessionDidResignActiveNotification, key: "session", paused: true)
        observeWorkspace(NSWorkspace.sessionDidBecomeActiveNotification, key: "session", paused: false)
        observeWorkspace(NSWorkspace.screensDidSleepNotification, key: "display", paused: true)
        observeWorkspace(NSWorkspace.screensDidWakeNotification, key: "display", paused: false)
        // Occlusion normally covers the lock screen; these also catch a locked session with displays on.
        for (name, paused) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            let token = DistributedNotificationCenter.default().addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setSuspended("locked", paused: paused) }
            }
            distributedObservers.append(token)
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.handleScroll(event) }
            return event
        }
        home()
    }

    private func observeWorkspace(_ name: Notification.Name, key: String, paused: Bool) {
        let token = NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.setSuspended(key, paused: paused) }
        }
        observers.append(token)
    }

    func cancelGesture() { cancelPull() }

    func setSuspended(_ key: String, paused: Bool) {
        guard environmentPaused.contains(key) != paused else { return }
        if paused { environmentPaused.insert(key); cancelPull() }
        else { environmentPaused.remove(key) }
        updateEligibility()
        if !paused { schedule.postpone(now: now) }
        updateStatus()
    }

    func windowVisibilityChanged() {
        cancelPull()
        updateEligibility()
        schedule.postpone(now: now)
    }

    /// Closing the window keeps the page alive for a quick reopen, but should not leave media playing unseen.
    func windowClosed() {
        webView.evaluateJavaScript("window.__xDesktop?.pauseMedia()", in: nil, in: WebsiteAdapter.world) { _ in }
        setSuspended("closed", paused: true)
    }

    func shutdown() {
        cancelPull()
        timer?.invalidate()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "websiteState", contentWorld: WebsiteAdapter.world)
    }

    func toggleAutomatic() {
        autoRefresh.toggle()
        defaults.set(autoRefresh, forKey: "autoRefresh")
        schedule.setEnabled(autoRefresh, now: now)
        updateStatus()
    }

    func home() {
        guard confirmDiscardIfNeeded(action: "Discard and Go Home") else { return }
        startNavigation()
        loadHomeDocument()
    }

    func back() {
        guard webView.canGoBack, confirmDiscardIfNeeded(action: "Discard and Go Back") else { return }
        startNavigation()
        webView.goBack()
    }

    func forward() {
        guard webView.canGoForward, confirmDiscardIfNeeded(action: "Discard and Go Forward") else { return }
        startNavigation()
        webView.goForward()
    }

    func zoomIn() { setZoom(Self.zoomLevels.first { $0 > pageZoom + 0.001 } ?? pageZoom) }
    func zoomOut() { setZoom(Self.zoomLevels.last { $0 < pageZoom - 0.001 } ?? pageZoom) }
    func resetZoom() { setZoom(1) }
    private func setZoom(_ value: Double) {
        guard value != pageZoom else { return }
        pageZoom = value
        webView.pageZoom = value
        defaults.set(value, forKey: "pageZoom")
    }

    /// Asks before quitting would discard a detected draft.
    func confirmQuit() -> Bool { confirmDiscardIfNeeded(action: "Discard and Quit") }

    func perform(_ action: Notice.Action) {
        switch action {
        case .openInBrowser(let url): NSWorkspace.shared.open(url)
        case .revealInFinder(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        notice = nil
        updateStatus()
    }

    private func loadHomeDocument() {
        if let fixtureURL {
            webView.loadFileURL(fixtureURL, allowingReadAccessTo: fixtureURL.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: URL(string: "https://x.com/home")!))
        }
    }

    /// A failed first load leaves no committed page, and WebKit then ignores reload().
    private func reloadDocument() {
        if webView.url == nil { loadHomeDocument() } else { webView.reload() }
    }

    private func isHomeURL(_ url: URL?) -> Bool {
        guard let fixtureURL else { return NavigationPolicy.isHome(url) }
        guard let url, url.isFileURL, url.fragment == nil else { return false }
        return url.resolvingSymlinksInPath().path == fixtureURL.resolvingSymlinksInPath().path
    }

    func refresh(manual: Bool = true, requiresAutomatic: Bool = false, requiresTop: Bool = false) {
        guard !schedule.loading, !checkingRefresh else { return }
        checkingRefresh = true
        // Consult the renderer immediately before reload, rather than trusting a
        // half-second-old observer message when a user may just have begun typing.
        webView.evaluateJavaScript("window.__xDesktop?.snapshot()", in: nil, in: WebsiteAdapter.world) { [weak self] result in
            guard let self else { return }
            self.checkingRefresh = false
            guard !self.schedule.loading else { return }
            if case .success(let body) = result, let fresh = WebsiteState.decode(body as Any) {
                self.page = fresh
            } else if !manual && self.schedule.retryAt == nil {
                // A retry reloads the page, which reinstalls the adapter.
                self.fail("Refresh paused: website state is unavailable.")
                return
            }
            if manual {
                guard self.confirmDiscardIfNeeded(action: "Discard and Reload") else { return }
            } else {
                guard !requiresTop || self.page.atTop else { return }
                guard !requiresAutomatic || (self.autoRefresh && !self.page.active && !self.pull.tracking) else { return }
                let retrying = self.schedule.retryAt != nil
                guard self.foregroundAvailable, !self.page.protected,
                      retrying || (self.page.home && self.page.ready) else {
                    self.updateEligibility()
                    self.updateStatus()
                    return
                }
            }
            self.startNavigation()
            self.reloadDocument()
        }
    }

    /// Only a detected draft justifies interrupting an explicit navigation. Media,
    /// focus, and dialogs simply end, as they would in a browser.
    private func confirmDiscardIfNeeded(action: String) -> Bool {
        guard page.draft else { return true }
        let alert = NSAlert()
        alert.messageText = "Discard your unsent post?"
        alert.informativeText = "X may not keep text or attachments you haven't posted."
        alert.addButton(withTitle: "Keep Editing")
        alert.addButton(withTitle: action).hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func startNavigation() {
        _ = schedule.begin()
        loading = true
        documentLoaded = false
        loadStarted = now
        errorMessage = nil
        feedFailed = false
        restoreFeed = defaults.object(forKey: "selectedFeed") as? Int
        if !(0...1).contains(restoreFeed ?? -1) { restoreFeed = nil }
        page = .empty
        cancelPull()
        updateEligibility()
        updateStatus()
    }

    private func completeIfReady() {
        guard documentLoaded, schedule.loading else { return }
        if page.home && page.failed {
            feedFailed = true
            fail("X could not load the feed.")
            return
        }
        // Home settles once the feed is ready and restored, or a pinned tab is showing.
        // Elsewhere, an unrecognized /home must not complete before the adapter reports.
        let settled = page.home ? page.otherTab || (page.ready && (restoreFeed == nil || page.selected == restoreFeed))
                                : !isHomeURL(webView.url)
        guard settled else { return }
        loadStarted = nil
        loading = false
        restoreFeed = nil
        schedule.succeeded(now: now)
        if page.ready {
            lastRefresh = Date()
            defaults.set(page.selected, forKey: "selectedFeed")
        }
        updateEligibility()
        updateStatus()
    }

    private func fail(_ message: String, manual: Bool = false, retryAfter: Double? = nil) {
        webView.stopLoading()
        loading = false
        loadStarted = nil
        errorMessage = message
        schedule.failed(now: now, retryAfter: retryAfter, requiresManual: manual)
        cancelPull()
        updateEligibility()
        updateStatus()
    }

    private func requestState() {
        webView.evaluateJavaScript("window.__xDesktop?.refreshState()", in: nil, in: WebsiteAdapter.world) { _ in }
    }

    private func showNotice(_ message: String, action: Notice.Action? = nil) {
        notice = Notice(message: message, action: action, expires: now + 12)
        updateStatus()
    }

    private func tick() {
        if canGoBack != webView.canGoBack { canGoBack = webView.canGoBack }
        if canGoForward != webView.canGoForward { canGoForward = webView.canGoForward }
        if let notice, now >= notice.expires { self.notice = nil }
        // Same-document history traversals in X's single-page app never call didFinish.
        // Once WebKit is idle, treat the document as loaded and ask for fresh state.
        if schedule.loading, !documentLoaded, !webView.isLoading, let loadStarted, now - loadStarted >= 0.5 {
            documentLoaded = true
            requestState()
            completeIfReady()
        }
        if let loadStarted, now - loadStarted >= loadTimeout {
            // Retry transient stalls; an unrecognizable feed needs a human, not more reloads.
            let unrecognized = documentLoaded && page.home && !page.recognized && !page.otherTab
            fail(unrecognized ? "X's feed layout wasn't recognized, so auto-refresh is paused."
                              : "The page did not become ready.", manual: unrecognized)
        }
        updateEligibility()
        let wheelRefresh = pull.finishWheelIfIdle(now: now, atTop: page.atTop, eligible: pullEligible)
        updatePullIndicator()
        if wheelRefresh { refresh(manual: false, requiresTop: true) }
        let mayRetry = foregroundAvailable && !page.protected && (webView.url == nil || isHomeURL(webView.url))
        if schedule.isDue(now: now, mayRetry: mayRetry, reading: !page.feedTop) {
            refresh(manual: false, requiresAutomatic: true)
        }
        updateStatus()
    }

    private func updateEligibility() {
        let eligible = foregroundAvailable && page.home && page.ready && !page.protected && errorMessage == nil
        schedule.setEligible(eligible, now: now)
        if page.active || pull.tracking { schedule.interacted(now: now) }
        if !eligible { cancelPull() }
    }

    private func updateStatus() {
        var text: String
        if let errorMessage { text = errorMessage }
        else if let notice { text = notice.message }
        else if loading { text = "Loading X" }
        else {
            // A page refresh time, never a claim that new posts arrived.
            let refreshed = lastRefresh.map { " · Refreshed \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            if !autoRefresh { text = "Auto-refresh paused" + (page.home ? refreshed : "") }
            else if !environmentPaused.isEmpty { text = "Auto-refresh suspended" }
            else if !page.reason.isEmpty { text = page.reason }
            else if page.ready { text = (page.feedTop ? "Auto-refresh every 60s" : "Auto-refresh waits while you read") + refreshed }
            else { text = "Waiting for the home feed" }
        }
        if text != status { status = text }
    }

    private func cancelPull() {
        pull.cancel()
        updatePullIndicator()
    }

    func handleScroll(_ event: NSEvent) {
        guard event.window === mainWindow else { cancelPull(); return }
        let point = webView.convert(event.locationInWindow, from: nil)
        guard webView.bounds.contains(point) else { cancelPull(); return }
        schedule.interacted(now: now)
        let phase: PullGesture.Phase
        if !event.momentumPhase.isEmpty { phase = .momentum }
        else if event.phase.contains(.cancelled) { phase = .cancelled }
        else if event.phase.contains(.ended) { phase = .ended }
        else if event.phase.contains(.began) { phase = .began }
        else if event.phase.contains(.changed) { phase = .changed }
        else if !event.phase.isEmpty { phase = .cancelled }
        else { phase = .unphased }
        // AppKit reports coarse wheels in lines and precise devices in points.
        // Normalize lines to a 16-point row; preserve the system's scroll direction.
        let scale = event.hasPreciseScrollingDeltas ? 1.0 : 16.0
        let dx = Double(event.scrollingDeltaX) * scale
        let dy = Double(event.scrollingDeltaY) * scale
        var shouldRefresh = false
        if phase == .unphased {
            pull.handleWheel(dx: dx, dy: dy, now: now, atTop: page.atTop, eligible: pullEligible)
        } else {
            shouldRefresh = pull.handle(phase: phase, dx: dx, dy: dy,
                atTop: page.atTop, eligible: pullEligible)
        }
        updatePullIndicator()
        if shouldRefresh { refresh(manual: false, requiresTop: true) }
    }

    /// Assign only on change: every @Published write invalidates SwiftUI, even with an equal value.
    private func updatePullIndicator() {
        let distance = min(pull.distance, 100)
        if pullDistance != distance { pullDistance = distance }
        if pullArmed != pull.armed { pullArmed = pull.armed }
        if pullUsesWheel != pull.usesWheel { pullUsesWheel = pull.usesWheel }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.name == "websiteState",
              message.webView === webView,
              NavigationPolicy.isX(message.frameInfo.request.url) ||
                (fixtureURL != nil && message.frameInfo.request.url?.isFileURL == true),
              let value = WebsiteState.decode(message.body) else { return }
        let previous = page
        page = value
        if !hasContent { hasContent = true }
        // A swipe cannot ask first, so it waits until any draft is resolved.
        if webView.allowsBackForwardNavigationGestures == value.draft { webView.allowsBackForwardNavigationGestures = !value.draft }
        if value.protected || !value.home { cancelPull() }
        if documentLoaded && value.otherTab {
            // X keeps its own pinned-tab choice; restoring For you or Following would override it.
            defaults.removeObject(forKey: "selectedFeed")
        } else if value.recognized && documentLoaded && (restoreFeed == nil || value.selected == restoreFeed) {
            defaults.set(value.selected, forKey: "selectedFeed")
            if previous.selected != value.selected { cancelPull(); schedule.postpone(now: now) }
        }
        // Recovering through X's own Retry clears our matching error.
        if feedFailed && !schedule.loading && value.home && value.ready {
            feedFailed = false
            errorMessage = nil
            schedule.succeeded(now: now)
        }
        // WebKit need not issue didFinish for an SPA history traversal. The
        // isolated adapter can establish readiness once native navigation is idle.
        if schedule.loading && !documentLoaded && !webView.isLoading && value.home && value.ready {
            documentLoaded = true
            if let restoreFeed, value.selected != restoreFeed {
                webView.evaluateJavaScript("window.__xDesktop?.restoreFeed(\(restoreFeed))", in: nil, in: WebsiteAdapter.world) { _ in }
            }
        }
        updateEligibility()
        completeIfReady()
        updateStatus()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        if !schedule.loading { startNavigation() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        documentLoaded = true
        if !hasContent { hasContent = true }
        // Give the page keyboard focus once, so scrolling keys and X's shortcuts work without a click.
        if !focusedWebView, let window = webView.window {
            focusedWebView = window.makeFirstResponder(webView)
        }
        if let restoreFeed, isHomeURL(webView.url) {
            webView.evaluateJavaScript("window.__xDesktop?.restoreFeed(\(restoreFeed))", in: nil, in: WebsiteAdapter.world) { _ in }
        }
        requestState()
        completeIfReady()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }
    private func handleNavigationError(_ error: Error) {
        let error = error as NSError
        // Cancellation, and a response handed off as a download, are not load failures.
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return }
        if error.domain == "WebKitErrorDomain" && error.code == 102 { return }
        fail("Could not load X. Check your connection or retry.")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        // State from the dead renderer is meaningless, including any draft it reported.
        page = .empty
        if let lastCrash, now - lastCrash < 300 {
            fail("The web process stopped again. Reload to continue.", manual: true)
        } else {
            // Recover once automatically; a repeat within five minutes waits for the user.
            lastCrash = now
            if schedule.loading { schedule.cancelled(now: now) }
            startNavigation()
            reloadDocument()
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse,
           response.statusCode == 429 {
            let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            fail("X limited requests. Refresh is suspended.", manual: seconds == nil, retryAfter: seconds)
            decisionHandler(.cancel)
        } else if navigationResponse.isForMainFrame && !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
        } else { decisionHandler(.allow) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.shouldPerformDownload && navigationAction.navigationType == .linkActivated {
            decisionHandler(.download); return
        }
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if NavigationPolicy.isX(url) || (fixtureURL != nil && url.isFileURL) {
            decisionHandler(.allow)
        } else if NavigationPolicy.isAuthentication(url) {
            // New windows retain the opener configuration supplied by WebKit.
            if navigationAction.targetFrame == nil { decisionHandler(.allow) }
            else { decisionHandler(.cancel); showAuthentication(url) }
        } else {
            decisionHandler(.cancel)
            guard NavigationPolicy.mayOpenExternally(url) else { return }
            // New windows can only be requested during a user gesture, because scripts may
            // not open windows automatically. Redirects and script navigations ask first.
            if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
                NSWorkspace.shared.open(url)
            } else {
                showNotice("Blocked a redirect to \(url.host ?? "another site").", action: .openInBrowser(url))
            }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if NavigationPolicy.isAuthentication(url) {
            return makeAuthenticationWindow(configuration: configuration)
        }
        if NavigationPolicy.isX(url) {
            if confirmDiscardIfNeeded(action: "Discard and Open Link") { webView.load(navigationAction.request) }
        } else if NavigationPolicy.mayOpenExternally(url) { NSWorkspace.shared.open(url) }
        return nil
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        adopt(download)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        adopt(download)
    }
    private func adopt(_ download: WKDownload) {
        download.delegate = self
        // The navigation that produced a download never replaces the page.
        guard schedule.loading else { return }
        loading = false
        loadStarted = nil
        schedule.cancelled(now: now)
        requestState()
        updateEligibility()
        updateStatus()
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping @MainActor @Sendable (URL?) -> Void) {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let name = (suggestedFilename as NSString).lastPathComponent
        let base = ((name.isEmpty ? "Download" : name) as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var destination = folder.appendingPathComponent(name.isEmpty ? "Download" : name)
        var copy = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent(ext.isEmpty ? "\(base) \(copy)" : "\(base) \(copy).\(ext)")
            copy += 1
        }
        downloadDestinations[ObjectIdentifier(download)] = destination
        completionHandler(destination)
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let destination = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        showNotice("Downloaded \(destination.lastPathComponent).", action: .revealInFinder(destination))
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        showNotice("The download could not be completed.")
    }

    private func showAuthentication(_ url: URL) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = webView.configuration.websiteDataStore
        makeAuthenticationWindow(configuration: configuration).load(URLRequest(url: url))
    }

    private func makeAuthenticationWindow(configuration: WKWebViewConfiguration) -> WKWebView {
        let authView = WKWebView(frame: .zero, configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Sign in to X"
        window.contentView = authView
        window.isReleasedWhenClosed = false
        let delegate = PopupDelegate(window: window, onClose: { [weak self, weak window] in
            guard let self else { return }
            self.popupWindows.removeAll { $0 === window }
            self.popupDelegates.removeAll { $0.window === window }
            self.setSuspended("authentication", paused: !self.popupWindows.isEmpty)
        }, onReturnedToX: { [weak self] in
            // The shared website data store now holds the session; load it in the main window.
            self?.home()
        })
        authView.navigationDelegate = delegate
        authView.uiDelegate = delegate
        window.delegate = delegate
        popupDelegates.append(delegate)
        popupWindows.append(window)
        setSuspended("authentication", paused: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        return authView
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        let handler: @MainActor (NSApplication.ModalResponse) -> Void = { completionHandler($0 == .OK ? panel.urls : nil) }
        if let window = webView.window { panel.beginSheetModal(for: window, completionHandler: handler) }
        else { panel.begin(completionHandler: handler) }
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
        let alert = NSAlert(); alert.messageText = message; alert.runModal(); completionHandler()
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
        let alert = NSAlert(); alert.messageText = message
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
}

@MainActor
private final class PopupDelegate: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    weak var window: NSWindow?
    let onClose: () -> Void
    let onReturnedToX: () -> Void
    private var visitedAuthentication = false
    init(window: NSWindow, onClose: @escaping () -> Void, onReturnedToX: @escaping () -> Void) {
        self.window = window; self.onClose = onClose; self.onReturnedToX = onReturnedToX
    }
    func windowWillClose(_ notification: Notification) { onClose() }
    func webViewDidClose(_ webView: WKWebView) { window?.close() }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if NavigationPolicy.isAuthentication(url) { visitedAuthentication = true }
        let allowed = NavigationPolicy.isX(url) || NavigationPolicy.isAuthentication(url) || url.absoluteString == "about:blank"
        if allowed { window?.title = "Sign in · \(url.host ?? "X")" }
        decisionHandler(allowed ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard visitedAuthentication, NavigationPolicy.isX(webView.url) else { return }
        // Opener-driven flows close their own popup. Otherwise the provider has returned to
        // X in this window, so hand the signed-in session back to the main window.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, let window = self.window, window.isVisible else { return }
            window.close()
            self.onReturnedToX()
        }
    }
}
