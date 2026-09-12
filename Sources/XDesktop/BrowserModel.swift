import AppKit
import Combine
import WebKit
import XCore

@MainActor
final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    @Published private(set) var status = "Loading X"
    @Published private(set) var loading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var autoRefresh: Bool
    @Published private(set) var pullDistance: Double = 0
    @Published private(set) var pullArmed = false
    @Published private(set) var pullUsesWheel = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastRefresh: Date?
    let webView: WKWebView
    private(set) var page = WebsiteState.empty
    private var schedule: RefreshSchedule
    private var pull = PullGesture()
    private let defaults: UserDefaults
    private let fixtureURL: URL?
    private var timer: Timer?
    private var eventMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var environmentPaused = Set<String>()
    private var documentLoaded = false
    private var checkingRefresh = false
    private var loadStarted: Double?
    private var restoreFeed: Int?
    private var popupWindows: [NSWindow] = []
    private var popupDelegates: [PopupDelegate] = []
    private weak var mainWindow: NSWindow?
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    private var foregroundAvailable: Bool {
        environmentPaused.isEmpty && mainWindow?.isVisible == true && mainWindow?.isMiniaturized == false
    }
    var pullEligible: Bool {
        foregroundAvailable && page.home && page.ready && !page.protected && !schedule.loading && errorMessage == nil
    }

    init(defaults: UserDefaults = .standard, fixtureURL: URL? = nil) {
        self.defaults = defaults
        self.fixtureURL = fixtureURL
        defaults.register(defaults: ["autoRefresh": true])
        autoRefresh = defaults.bool(forKey: "autoRefresh")
        schedule = RefreshSchedule(enabled: defaults.bool(forKey: "autoRefresh"))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = fixtureURL == nil ? .default() : .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        observeWorkspace(NSWorkspace.willSleepNotification, key: "sleep", paused: true)
        observeWorkspace(NSWorkspace.didWakeNotification, key: "sleep", paused: false)
        observeWorkspace(NSWorkspace.sessionDidResignActiveNotification, key: "session", paused: true)
        observeWorkspace(NSWorkspace.sessionDidBecomeActiveNotification, key: "session", paused: false)
        observeWorkspace(NSWorkspace.screensDidSleepNotification, key: "display", paused: true)
        observeWorkspace(NSWorkspace.screensDidWakeNotification, key: "display", paused: false)
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
    }

    func windowVisibilityChanged() {
        cancelPull()
        updateEligibility()
        schedule.postpone(now: now)
    }

    func shutdown() {
        cancelPull()
        timer?.invalidate()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "websiteState", contentWorld: WebsiteAdapter.world)
    }

    func toggleAutomatic() {
        autoRefresh.toggle()
        defaults.set(autoRefresh, forKey: "autoRefresh")
        schedule.setEnabled(autoRefresh, now: now)
        updateStatus()
    }

    func home() {
        guard confirmDiscardIfNeeded() else { return }
        if let fixtureURL {
            startNavigation()
            webView.loadFileURL(fixtureURL, allowingReadAccessTo: fixtureURL.deletingLastPathComponent())
        } else {
            startNavigation()
            webView.load(URLRequest(url: URL(string: "https://x.com/home")!))
        }
    }

    func back() {
        guard webView.canGoBack, confirmDiscardIfNeeded() else { return }
        startNavigation()
        webView.goBack()
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
                self.errorMessage = "Refresh paused: website state is unavailable."
                self.updateEligibility()
                self.updateStatus()
                return
            }
            if manual {
                guard self.confirmDiscardIfNeeded() else { return }
            } else {
                guard !requiresTop || self.page.atTop else { return }
                guard !requiresAutomatic || (self.autoRefresh && !self.page.scrolling && !self.pull.tracking) else { return }
                let retrying = self.schedule.retryAt != nil
                guard self.foregroundAvailable, !self.page.protected,
                      retrying || (self.page.home && self.page.ready) else {
                    self.updateEligibility()
                    self.updateStatus()
                    return
                }
            }
            self.startNavigation()
            self.webView.reload()
        }
    }

    private func confirmDiscardIfNeeded() -> Bool {
        guard page.protected else { return true }
        let alert = NSAlert()
        alert.messageText = "Reload or leave this page?"
        alert.informativeText = "This may discard a draft or interrupt media."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Continue")
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func startNavigation() {
        _ = schedule.begin()
        loading = true
        documentLoaded = false
        loadStarted = now
        errorMessage = nil
        restoreFeed = defaults.object(forKey: "selectedFeed") as? Int
        if !(0...1).contains(restoreFeed ?? -1) { restoreFeed = nil }
        page = .empty
        cancelPull()
        updateEligibility()
        updateStatus()
    }

    private func completeIfReady() {
        guard documentLoaded, schedule.loading else { return }
        if page.home && (!page.ready || (restoreFeed != nil && page.selected != restoreFeed)) { return }
        // Unrecognized /home must not complete before the adapter establishes readiness.
        if (NavigationPolicy.isHome(webView.url) || fixtureURL != nil) && !page.ready { return }
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

    private func tick() {
        if canGoBack != webView.canGoBack { canGoBack = webView.canGoBack }
        if let loadStarted, now - loadStarted >= 45 {
            fail("The page did not become ready. Try Reload.", manual: true)
        }
        updateEligibility()
        let wheelRefresh = pull.finishWheelIfIdle(now: now, atTop: page.atTop, eligible: pullEligible)
        updatePullIndicator()
        if wheelRefresh { refresh(manual: false, requiresTop: true) }
        let mayRetry = foregroundAvailable && !page.protected &&
            (NavigationPolicy.isHome(webView.url) || fixtureURL != nil)
        if schedule.isDue(now: now, mayRetry: mayRetry) { refresh(manual: false, requiresAutomatic: true) }
        updateStatus()
    }

    private func updateEligibility() {
        let eligible = foregroundAvailable && page.home && page.ready && !page.protected && errorMessage == nil
        schedule.setEligible(eligible, now: now)
        if page.scrolling || pull.tracking { schedule.scrolled(now: now) }
        if !eligible { cancelPull() }
    }

    private func updateStatus() {
        let text: String
        if let errorMessage { text = errorMessage }
        else if loading { text = "Loading X" }
        else if !autoRefresh { text = "Auto-refresh paused" }
        else if !environmentPaused.isEmpty { text = "Auto-refresh suspended" }
        else if !page.reason.isEmpty { text = page.reason }
        else if page.ready { text = "Auto-refresh on · 60s" }
        else if page.home { text = "Waiting for the home feed" }
        else { text = "Sign in to load your feeds" }
        if text != status { status = text }
    }

    private func cancelPull() {
        pull.cancel()
        if pullDistance != 0 { pullDistance = 0 }
        if pullArmed { pullArmed = false }
        if pullUsesWheel { pullUsesWheel = false }
    }

    func handleScroll(_ event: NSEvent) {
        guard event.window === mainWindow else { cancelPull(); return }
        let point = webView.convert(event.locationInWindow, from: nil)
        guard webView.bounds.contains(point) else { cancelPull(); return }
        schedule.scrolled(now: now)
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

    private func updatePullIndicator() {
        pullDistance = min(pull.distance, 100)
        pullArmed = pull.armed
        pullUsesWheel = pull.usesWheel
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.name == "websiteState",
              message.webView === webView,
              NavigationPolicy.isX(message.frameInfo.request.url) ||
                (fixtureURL != nil && message.frameInfo.request.url?.isFileURL == true),
              let value = WebsiteState.decode(message.body) else { return }
        let previous = page
        page = value
        if value.protected || !value.home { cancelPull() }
        if value.recognized && documentLoaded && (restoreFeed == nil || value.selected == restoreFeed) {
            defaults.set(value.selected, forKey: "selectedFeed")
            if previous.selected != value.selected { cancelPull(); schedule.postpone(now: now) }
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
        if let restoreFeed, NavigationPolicy.isHome(webView.url) || fixtureURL != nil {
            webView.evaluateJavaScript("window.__xDesktop?.restoreFeed(\(restoreFeed))", in: nil, in: WebsiteAdapter.world) { _ in }
        }
        webView.evaluateJavaScript("window.__xDesktop?.refreshState()", in: nil, in: WebsiteAdapter.world) { _ in }
        completeIfReady()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }
    private func handleNavigationError(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        fail("Could not load X. Check your connection or retry.")
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail("The web process stopped. Reload to continue.", manual: true)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse,
           response.statusCode == 429 {
            let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            fail("X limited requests. Refresh is suspended.", manual: seconds == nil, retryAfter: seconds)
            decisionHandler(.cancel)
        } else { decisionHandler(.allow) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if NavigationPolicy.isX(url) || (fixtureURL != nil && url.isFileURL) {
            decisionHandler(.allow)
        } else if NavigationPolicy.isAuthentication(url) {
            // New windows retain the opener configuration supplied by WebKit.
            if navigationAction.targetFrame == nil { decisionHandler(.allow) }
            else { decisionHandler(.cancel); showAuthentication(url) }
        } else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated && NavigationPolicy.mayOpenExternally(url) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if NavigationPolicy.isAuthentication(url) {
            return makeAuthenticationWindow(configuration: configuration)
        }
        if NavigationPolicy.isX(url) { webView.load(navigationAction.request) }
        else if NavigationPolicy.mayOpenExternally(url) { NSWorkspace.shared.open(url) }
        return nil
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
        let delegate = PopupDelegate(window: window) { [weak self, weak window] in
            guard let self else { return }
            self.popupWindows.removeAll { $0 === window }
            self.popupDelegates.removeAll { $0.window === window }
            self.setSuspended("authentication", paused: !self.popupWindows.isEmpty)
        }
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
        panel.begin { response in completionHandler(response == .OK ? panel.urls : nil) }
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
    init(window: NSWindow, onClose: @escaping () -> Void) { self.window = window; self.onClose = onClose }
    func windowWillClose(_ notification: Notification) { onClose() }
    func webViewDidClose(_ webView: WKWebView) { window?.close() }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let allowed = NavigationPolicy.isX(url) || NavigationPolicy.isAuthentication(url) || url.absoluteString == "about:blank"
        if allowed { window?.title = "Sign in · \(url.host ?? "X")" }
        decisionHandler(allowed ? .allow : .cancel)
    }
}
