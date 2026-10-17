import AppKit
import SwiftUI
import WebKit
import XCore

@main
struct XDesktopMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate, NSMenuItemValidation {
    private var window: NSWindow!
    private var model: BrowserModel!
    private var titleUpdates: Task<Void, Never>?
    private let updates = Updates()
    private var preferences: AppPreferences!
    private var settingsWindow: SettingsWindow!
    private let notifier = UnreadNotifier()
    /// Links that arrived before the window existed (a Dock drop that launched the app).
    private var pendingLinks: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        var fixture: URL?
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--fixture"), CommandLine.arguments.indices.contains(index + 1) {
            fixture = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        #endif
        // One feed window; tabbing would only add empty View-menu commands.
        NSWindow.allowsAutomaticWindowTabbing = false
        let defaults = fixture == nil ? UserDefaults.standard : UserDefaults(suiteName: "as.banast.xdesktop.fixture")!
        model = BrowserModel(defaults: defaults, fixtureURL: fixture)
        preferences = AppPreferences(defaults: defaults)
        settingsWindow = SettingsWindow(model: model, preferences: preferences, updates: updates)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = fixture == nil ? "X" : "X · Test fixture"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.titlebarSeparatorStyle = .none
        window.collectionBehavior.insert(.fullScreenPrimary)
        let toolbar = NSToolbar(identifier: "XToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.centeredItemIdentifiers = [Self.feedItem]
        window.toolbar = toolbar
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        window.minSize = NSSize(width: 360, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView(model: model, openSettings: { [weak self] in self?.showSettings() }))
        preferences.onKeepOnTop = { [weak self] onTop in self?.window.level = onTop ? .floating : .normal }
        window.level = preferences.keepOnTop ? .floating : .normal
        window.center()
        // Fixture runs are throwaway; keep their geometry out of the real preferences.
        if fixture == nil { window.setFrameAutosaveName("XMainWindow") }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }) { window.center() }
        if let screen = window.screen {
            var frame = window.frame
            frame.size.width = min(frame.width, screen.visibleFrame.width)
            frame.size.height = min(frame.height, screen.visibleFrame.height)
            window.setFrame(frame, display: false)
        }
        installMenus()
        // X's title carries the unread notification count; show it on the Dock icon,
        // and name the window after the page for the Window menu and Mission Control.
        let model = self.model!, namesWindow = fixture == nil
        titleUpdates = Task { [weak self] in
            for await title in Observations({ model.pageTitle }) {
                let badge = PageTitle.badge(title)
                NSApp.dockTile.badgeLabel = badge
                if namesWindow { self?.window.title = PageTitle.text(title) }
                if let self { self.notifier.update(badge: badge, enabled: self.preferences.notifyUnread) }
            }
        }
        // Services › Open in X for macOS, for an x.com link selected in another app.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        model.attach(to: window)
        pendingLinks.forEach(open)
        pendingLinks = []
    }

    /// A link or .webloc dropped on the Dock icon, or a file opened with the app.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if model == nil { pendingLinks.append(url) } else { open(url) }
        }
    }

    private func open(_ url: URL) {
        let link: URL?
        if url.isFileURL {
            // Finder's .webloc is a property list; Windows-style .url files are "URL=" text.
            let data = try? Data(contentsOf: url)
            let plist = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
            let text = (plist?["URL"] as? String)
                ?? data.flatMap { String(data: $0, encoding: .utf8) }?.split(separator: "\n")
                    .first { $0.hasPrefix("URL=") }.map { String($0.dropFirst(4)) }
            link = text.flatMap(NavigationPolicy.xLink(from:))
        } else {
            link = NavigationPolicy.xLink(from: url.absoluteString)
        }
        showMainWindow()
        if let link { model.open(link) } else { model.open(url) }
    }

    /// The Services menu handler named in Info.plist (NSMessage openXLink).
    @objc func openXLink(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let text = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string) ?? ""
        guard let url = NavigationPolicy.xLink(from: text) else {
            error.pointee = "The selection isn't an x.com link."
            return
        }
        NSApp.activate()
        showMainWindow()
        model.open(url)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Without a draft the answer arrives immediately; otherwise a sheet replies later.
        let reply = QuitReply()
        model.confirmQuit { quit in
            if reply.deferred { sender.reply(toApplicationShouldTerminate: quit) } else { reply.answer = quit }
        }
        if let answer = reply.answer { return answer ? .terminateNow : .terminateCancel }
        reply.deferred = true
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
    func windowWillClose(_ notification: Notification) { model.windowClosed() }
    func windowDidBecomeKey(_ notification: Notification) { model.setSuspended("closed", paused: false) }
    func windowDidMiniaturize(_ notification: Notification) { model.windowVisibilityChanged() }
    func windowDidDeminiaturize(_ notification: Notification) { model.windowVisibilityChanged() }
    func windowDidChangeOcclusionState(_ notification: Notification) { model.windowVisibilityChanged() }
    func applicationDidHide(_ notification: Notification) { model.setSuspended("hidden", paused: true) }
    func applicationDidUnhide(_ notification: Notification) { model.setSuspended("hidden", paused: false) }
    func windowDidResignKey(_ notification: Notification) { model.cancelGesture() }

    @objc private func refresh() { model.refresh() }
    @objc private func stop() { model.stop() }
    @objc private func home() { model.home() }
    @objc private func back() { model.back() }
    @objc private func forward() { model.forward() }
    @objc private func selectForYou() { model.selectFeed(0) }
    @objc private func selectFollowing() { model.selectFeed(1) }
    @objc private func toggleFollowingRecent() { model.toggleFollowingRecent() }
    @objc private func copyLink() { model.copyLink() }
    @objc private func openInBrowser() { model.openInBrowser() }
    @objc private func showFind() { model.showFind() }
    @objc private func findNext() { model.findNext() }
    @objc private func findPrevious() { model.findNext(backwards: true) }
    @objc private func toggleAutomatic() { model.toggleAutomatic() }
    @objc private func checkForUpdates() { updates.checkNow() }
    @objc private func toggleAutomaticUpdates() { updates.checksAutomatically.toggle() }
    @objc private func showSettings() {
        settingsWindow.show()
        NSApp.activate()
    }
    @objc private func toggleKeepOnTop() { preferences.keepOnTop.toggle() }
    @objc private func openWebsite() { NSWorkspace.shared.open(URL(string: "https://x.banast.as")!) }
    @objc private func reportIssue() { NSWorkspace.shared.open(URL(string: "https://github.com/banastas/X/issues")!) }
    @objc private func copyDiagnostics() {
        model.copyDiagnostics(updates: updates.isAvailable ? (updates.checksAutomatically ? "checking daily" : "manual only")
                                                           : "not in this build")
    }
    @objc private func zoomIn() { model.zoomIn() }
    @objc private func zoomOut() { model.zoomOut() }
    @objc private func actualSize() { model.resetZoom() }
    @objc private func showMainWindow() {
        window.makeKeyAndOrderFront(nil)
        model.windowVisibilityChanged()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(back): return model.canGoBack
        case #selector(forward): return model.canGoForward
        case #selector(refresh): return !model.loading
        case #selector(stop): return model.loading
        case #selector(copyLink), #selector(openInBrowser): return model.currentLink != nil
        case #selector(selectForYou), #selector(selectFollowing):
            let index = menuItem.action == #selector(selectForYou) ? 0 : 1
            menuItem.state = model.page.home && model.page.recognized && model.page.selected == index ? .on : .off
            return true
        case #selector(toggleFollowingRecent):
            menuItem.state = model.followingRecent ? .on : .off
            return true
        case #selector(toggleAutomatic):
            menuItem.title = model.autoRefresh ? "Pause Auto-refresh" : "Resume Auto-refresh"
            return true
        case #selector(checkForUpdates): return updates.canCheck
        case #selector(toggleAutomaticUpdates):
            menuItem.state = updates.checksAutomatically ? .on : .off
            return true
        case #selector(toggleKeepOnTop):
            menuItem.state = preferences.keepOnTop ? .on : .off
            return true
        case #selector(zoomIn): return model.canZoomIn
        case #selector(zoomOut): return model.canZoomOut
        case #selector(actualSize): return model.pageZoom != 1
        default: return true
        }
    }

    private static let navigationItem = NSToolbarItem.Identifier("XNavigation")
    private static let refreshItem = NSToolbarItem.Identifier("XRefresh")
    private static let feedItem = NSToolbarItem.Identifier("XFeed")

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.navigationItem, .flexibleSpace, Self.feedItem, .flexibleSpace, Self.refreshItem]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == Self.feedItem {
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Feed"
            item.view = NSHostingView(rootView: FeedLabel(model: model))
            return item
        }
        guard identifier == Self.navigationItem || identifier == Self.refreshItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = identifier == Self.navigationItem ? "Navigation" : "Refresh"
        item.view = NSHostingView(rootView: ToolbarControls(model: model, navigation: identifier == Self.navigationItem))
        return item
    }

    private func installMenus() {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command,
                 to parent: NSMenu, target: AnyObject? = nil) -> NSMenuItem {
            let item = parent.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            return item
        }
        func submenu(_ title: String, in parent: NSMenu) -> NSMenu {
            let child = NSMenu(title: title)
            let item = parent.addItem(withTitle: title, action: nil, keyEquivalent: "")
            item.submenu = child
            return child
        }

        let appMenu = submenu("X", in: menu)
        _ = add("About X", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), to: appMenu)
        // Only published builds installed in Applications have an updater (Updates).
        if updates.isAvailable {
            _ = add("Check for Updates…", #selector(checkForUpdates), to: appMenu, target: self)
            _ = add("Check for Updates Automatically", #selector(toggleAutomaticUpdates), to: appMenu, target: self)
        }
        appMenu.addItem(.separator())
        _ = add("Settings…", #selector(showSettings), ",", to: appMenu, target: self)
        appMenu.addItem(.separator())
        NSApp.servicesMenu = submenu("Services", in: appMenu)
        appMenu.addItem(.separator())
        _ = add("Hide X", #selector(NSApplication.hide(_:)), "h", to: appMenu)
        _ = add("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], to: appMenu)
        _ = add("Show All", #selector(NSApplication.unhideAllApplications(_:)), to: appMenu)
        appMenu.addItem(.separator())
        _ = add("Quit X", #selector(NSApplication.terminate(_:)), "q", to: appMenu)

        let file = submenu("File", in: menu)
        _ = add("Copy Link", #selector(copyLink), "c", [.command, .shift], to: file, target: self)
        _ = add("Open in Browser", #selector(openInBrowser), "o", [.command, .shift], to: file, target: self)

        let edit = submenu("Edit", in: menu)
        _ = add("Undo", Selector(("undo:")), "z", to: edit)
        _ = add("Redo", Selector(("redo:")), "z", [.command, .shift], to: edit)
        edit.addItem(.separator())
        _ = add("Cut", #selector(NSText.cut(_:)), "x", to: edit)
        _ = add("Copy", #selector(NSText.copy(_:)), "c", to: edit)
        _ = add("Paste", #selector(NSText.paste(_:)), "v", to: edit)
        _ = add("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift], to: edit)
        _ = add("Delete", #selector(NSText.delete(_:)), to: edit)
        _ = add("Select All", #selector(NSText.selectAll(_:)), "a", to: edit)
        edit.addItem(.separator())
        let find = submenu("Find", in: edit)
        _ = add("Find…", #selector(showFind), "f", to: find, target: self)
        _ = add("Find Next", #selector(findNext), "g", to: find, target: self)
        _ = add("Find Previous", #selector(findPrevious), "g", [.command, .shift], to: find, target: self)
        edit.addItem(.separator())
        let spelling = submenu("Spelling and Grammar", in: edit)
        _ = add("Show Spelling and Grammar", #selector(NSText.showGuessPanel(_:)), ":", to: spelling)
        _ = add("Check Document Now", #selector(NSText.checkSpelling(_:)), ";", to: spelling)
        spelling.addItem(.separator())
        _ = add("Check Spelling While Typing", #selector(NSTextView.toggleContinuousSpellChecking(_:)), to: spelling)
        _ = add("Check Grammar With Spelling", #selector(NSTextView.toggleGrammarChecking(_:)), to: spelling)
        _ = add("Correct Spelling Automatically", #selector(NSTextView.toggleAutomaticSpellingCorrection(_:)), to: spelling)
        let substitutions = submenu("Substitutions", in: edit)
        _ = add("Show Substitutions", #selector(NSTextView.orderFrontSubstitutionsPanel(_:)), to: substitutions)
        substitutions.addItem(.separator())
        _ = add("Smart Copy/Paste", #selector(NSTextView.toggleSmartInsertDelete(_:)), to: substitutions)
        _ = add("Smart Quotes", #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)), to: substitutions)
        _ = add("Smart Dashes", #selector(NSTextView.toggleAutomaticDashSubstitution(_:)), to: substitutions)
        _ = add("Smart Links", #selector(NSTextView.toggleAutomaticLinkDetection(_:)), to: substitutions)
        _ = add("Text Replacement", #selector(NSTextView.toggleAutomaticTextReplacement(_:)), to: substitutions)

        let view = submenu("View", in: menu)
        _ = add("Refresh", #selector(refresh), "r", to: view, target: self)
        _ = add("Stop", #selector(stop), ".", to: view, target: self)
        _ = add("Home", #selector(home), "1", to: view, target: self)
        _ = add("Back", #selector(back), "[", to: view, target: self)
        _ = add("Forward", #selector(forward), "]", to: view, target: self)
        view.addItem(.separator())
        _ = add("For You", #selector(selectForYou), "1", [.command, .option], to: view, target: self)
        _ = add("Following", #selector(selectFollowing), "2", [.command, .option], to: view, target: self)
        _ = add("Default Following to Recent", #selector(toggleFollowingRecent), to: view, target: self)
        view.addItem(.separator())
        _ = add("Pause Auto-refresh", #selector(toggleAutomatic), "p", to: view, target: self)
        view.addItem(.separator())
        _ = add("Actual Size", #selector(actualSize), "0", to: view, target: self)
        _ = add("Zoom In", #selector(zoomIn), "+", to: view, target: self)
        // ⌘= is the unshifted Zoom In key on most layouts.
        let zoomInAlternate = add("Zoom In", #selector(zoomIn), "=", to: view, target: self)
        zoomInAlternate.isHidden = true
        zoomInAlternate.allowsKeyEquivalentWhenHidden = true
        _ = add("Zoom Out", #selector(zoomOut), "-", to: view, target: self)
        view.addItem(.separator())
        _ = add("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control], to: view)

        let windowMenu = submenu("Window", in: menu)
        _ = add("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", to: windowMenu)
        _ = add("Zoom", #selector(NSWindow.performZoom(_:)), to: windowMenu)
        _ = add("Close", #selector(NSWindow.performClose(_:)), "w", to: windowMenu)
        windowMenu.addItem(.separator())
        _ = add("Show Main Window", #selector(showMainWindow), to: windowMenu, target: self)
        _ = add("Keep on Top", #selector(toggleKeepOnTop), to: windowMenu, target: self)
        windowMenu.addItem(.separator())
        _ = add("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), to: windowMenu)
        NSApp.windowsMenu = windowMenu

        let help = submenu("Help", in: menu)
        _ = add("X for macOS Website", #selector(openWebsite), to: help, target: self)
        _ = add("Report an Issue…", #selector(reportIssue), to: help, target: self)
        help.addItem(.separator())
        _ = add("Copy Diagnostics", #selector(copyDiagnostics), to: help, target: self)
        NSApp.helpMenu = help
        NSApp.mainMenu = menu
    }
}

/// Carries an answer from a quit confirmation that may arrive before or after
/// `applicationShouldTerminate` returns.
@MainActor
private final class QuitReply {
    var deferred = false
    var answer: Bool?
}

private struct WebViewHost: NSViewRepresentable {
    let model: BrowserModel
    func makeNSView(context: Context) -> WKWebView { model.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private struct ContentView: View {
    let model: BrowserModel
    let openSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsDetails = false

    private var pullLabel: String {
        if model.pullArmed { return model.pullUsesWheel ? "Stop scrolling to refresh" : "Release to refresh" }
        return model.pullUsesWheel ? "Keep scrolling to refresh" : "Pull to refresh"
    }

    /// The status line while automatic refresh is simply counting down.
    private func countdown(to next: Date, at date: Date) -> String {
        let seconds = Int(next.timeIntervalSince(date).rounded(.up))
        let refreshed = model.lastRefresh.map { " · Refreshed \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        return (seconds > 0 ? "Next refresh in \(RefreshInterval.remaining(seconds))" : "Refreshing once you pause") + refreshed
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.findVisible {
                FindBar(model: model)
                Divider()
            }
            ZStack(alignment: .top) {
                WebViewHost(model: model)
                if !model.hasContent {
                    // Cover the empty web view until the first document draws, avoiding a white launch flash.
                    Color(nsColor: .windowBackgroundColor).allowsHitTesting(false)
                    if !model.loading { LoadProblem(model: model) }
                }
                if model.pullDistance > 0 {
                    Label(pullLabel, systemImage: model.pullArmed ? "arrow.clockwise" : "arrow.down")
                        .font(.caption).padding(10).background(.regularMaterial, in: Capsule())
                        .padding(.top, min(model.pullDistance / 3, 24))
                        .allowsHitTesting(false)
                } else if model.loading {
                    ProgressView().controlSize(.small).padding(10)
                        .background(.regularMaterial, in: Capsule()).padding(.top, 8).allowsHitTesting(false)
                        .accessibilityLabel("Loading")
                }
            }
            Divider()
            HStack(spacing: 8) {
                // The status opens a short explanation of what refresh is waiting for.
                Button { showsDetails.toggle() } label: {
                    Group {
                        if let next = model.nextRefresh {
                            TimelineView(.periodic(from: .now, by: 1)) { context in Text(countdown(to: next, at: context.date)) }
                        } else {
                            Text(model.status)
                        }
                    }
                    .font(.system(size: 11)).lineLimit(model.errorMessage == nil ? 1 : 2).foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show refresh details")
                .accessibilityLabel(model.status)
                .accessibilityHint("Shows what automatic refresh is waiting for")
                .popover(isPresented: $showsDetails, arrowEdge: .top) {
                    StatusDetails(model: model, openSettings: { showsDetails = false; openSettings() })
                }
                Spacer(minLength: 0)
                if model.errorMessage != nil {
                    Button("Retry") { model.refresh() }.font(.caption)
                } else if let action = model.notice?.action {
                    Button(action.title) { model.perform(action) }.font(.caption)
                }
            }.padding(.horizontal, 10).padding(.vertical, 3)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: model.pullArmed)
    }
}

/// The status strip's popover: what refresh is doing and why, with the controls that change it.
private struct StatusDetails: View {
    let model: BrowserModel
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.status).font(.headline).fixedSize(horizontal: false, vertical: true)
            ForEach(model.refreshDetails, id: \.self) { line in
                Text(line).fixedSize(horizontal: false, vertical: true)
            }
            if let last = model.lastRefresh {
                Text("Last refreshed at \(last.formatted(date: .omitted, time: .standard))").foregroundStyle(.secondary)
            }
            HStack {
                Button("Refresh Now") { model.refresh() }.disabled(model.loading)
                Button(model.autoRefresh ? "Pause" : "Resume", action: model.toggleAutomatic)
                Spacer()
                Button("Settings…", action: openSettings)
            }
            .padding(.top, 4)
        }
        .font(.callout)
        .padding(16)
        .frame(width: 320)
    }
}

/// The feed being shown, centered in the toolbar. The toolbar draws it as a button, so it is one:
/// a menu that switches feeds, or returns Home from elsewhere.
private struct FeedLabel: View {
    let model: BrowserModel

    var body: some View {
        Menu {
            Button("For You") { model.selectFeed(0) }
            Button("Following") { model.selectFeed(1) }
            Divider()
            Button("Home", action: model.home)
        } label: {
            Text(model.feedLabel.isEmpty ? "Home" : model.feedLabel)
                .font(.system(size: 12, weight: .semibold)).lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .fixedSize()
        // A toolbar item keeps the size it had when inserted, so reserve room for the longest label.
        .frame(width: 110, height: 26)
        .help("Switch feeds")
        .accessibilityLabel(model.feedLabel.isEmpty ? "Feed menu" : "Showing \(model.feedLabel)")
        .accessibilityHint("Switches between For you and Following")
    }
}

/// Shown in place of the page when nothing has loaded yet, so a failed launch is not a blank window.
private struct LoadProblem: View {
    let model: BrowserModel

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 34)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("X didn't load").font(.headline)
            Text(model.errorMessage ?? "Loading stopped.").font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again") { model.refresh() }.keyboardShortcut(.defaultAction).padding(.top, 4)
        }
        .padding(24).frame(maxWidth: 320).frame(maxHeight: .infinity)
    }
}

private struct FindBar: View {
    @Bindable var model: BrowserModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Find on page", text: $model.findQuery)
                .textFieldStyle(.plain).focused($focused)
                .onSubmit { model.findNext() }
                .onChange(of: model.findQuery) { _, query in model.find(query) }
            if model.findMissing { Text("Not found").foregroundStyle(.secondary) }
            Button { model.findNext(backwards: true) } label: { Image(systemName: "chevron.up").frame(width: 20, height: 20) }
                .help("Previous (⇧⌘G)").accessibilityLabel("Previous match")
            Button { model.findNext() } label: { Image(systemName: "chevron.down").frame(width: 20, height: 20) }
                .help("Next (⌘G)").accessibilityLabel("Next match")
            Button("Done", action: model.hideFind)
        }
        .font(.system(size: 12)).buttonStyle(.borderless)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .onExitCommand(perform: model.hideFind)
        .onAppear { focused = true }
        .onChange(of: model.findRequest) { focused = true }
    }
}

private struct ToolbarControls: View {
    let model: BrowserModel
    let navigation: Bool

    var body: some View {
        HStack(spacing: 4) {
            if navigation {
                // Navigation stays available during loads; it simply starts a new one.
                Button(action: model.back) { Image(systemName: "chevron.left").frame(width: 24, height: 24) }
                    .disabled(!model.canGoBack)
                    .help("Back (⌘[)").accessibilityLabel("Back")
                Button(action: model.forward) { Image(systemName: "chevron.right").frame(width: 24, height: 24) }
                    .disabled(!model.canGoForward)
                    .help("Forward (⌘])").accessibilityLabel("Forward")
                Button(action: model.home) { Image(systemName: "house").frame(width: 24, height: 24) }
                    .help("Home (⌘1)").accessibilityLabel("Home")
            } else {
                // While a load is under way, the same place stops it.
                if model.loading {
                    Button(action: model.stop) { Image(systemName: "xmark").frame(width: 24, height: 24) }
                        .help("Stop loading (⌘.)").accessibilityLabel("Stop")
                } else {
                    Button { model.refresh() } label: { Image(systemName: "arrow.clockwise").frame(width: 24, height: 24) }
                        .help("Refresh (⌘R)").accessibilityLabel("Refresh")
                }
                // A timer, not play/pause, so it cannot be mistaken for a media control.
                Button(action: model.toggleAutomatic) {
                    Image(systemName: model.autoRefresh ? "timer.circle.fill" : "timer.circle")
                        .foregroundStyle(model.autoRefresh ? Color.accentColor : Color.secondary)
                        .frame(width: 24, height: 24)
                }
                .help(model.autoRefresh ? "Auto-refresh is on. Click to pause (⌘P)" : "Auto-refresh is paused. Click to resume (⌘P)")
                .accessibilityLabel("Automatic refresh")
                .accessibilityValue(model.autoRefresh ? "On" : "Paused")
                .accessibilityHint(model.autoRefresh ? "Pauses automatic refresh" : "Resumes automatic refresh")
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .frame(width: navigation ? 84 : 56, height: 26)
    }
}
