import AppKit
import SwiftUI
import WebKit

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        var fixture: URL?
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--fixture"), CommandLine.arguments.indices.contains(index + 1) {
            fixture = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        #endif
        // One feed window; tabbing would only add empty View-menu commands.
        NSWindow.allowsAutomaticWindowTabbing = false
        model = BrowserModel(defaults: fixture == nil ? .standard : UserDefaults(suiteName: "as.banast.xdesktop.fixture")!, fixtureURL: fixture)
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
        window.toolbar = toolbar
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        window.minSize = NSSize(width: 360, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView(model: model))
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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        model.attach(to: window)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.confirmQuit() ? .terminateNow : .terminateCancel
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
    @objc private func home() { model.home() }
    @objc private func back() { model.back() }
    @objc private func forward() { model.forward() }
    @objc private func toggleAutomatic() { model.toggleAutomatic() }
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
        case #selector(toggleAutomatic):
            menuItem.title = model.autoRefresh ? "Pause Auto-refresh" : "Resume Auto-refresh"
            return true
        case #selector(zoomIn): return model.canZoomIn
        case #selector(zoomOut): return model.canZoomOut
        case #selector(actualSize): return model.pageZoom != 1
        default: return true
        }
    }

    private static let navigationItem = NSToolbarItem.Identifier("XNavigation")
    private static let refreshItem = NSToolbarItem.Identifier("XRefresh")

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.navigationItem, .flexibleSpace, Self.refreshItem]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
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
        appMenu.addItem(.separator())
        NSApp.servicesMenu = submenu("Services", in: appMenu)
        appMenu.addItem(.separator())
        _ = add("Hide X", #selector(NSApplication.hide(_:)), "h", to: appMenu)
        _ = add("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], to: appMenu)
        _ = add("Show All", #selector(NSApplication.unhideAllApplications(_:)), to: appMenu)
        appMenu.addItem(.separator())
        _ = add("Quit X", #selector(NSApplication.terminate(_:)), "q", to: appMenu)

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
        _ = add("Home", #selector(home), "1", to: view, target: self)
        _ = add("Back", #selector(back), "[", to: view, target: self)
        _ = add("Forward", #selector(forward), "]", to: view, target: self)
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
        windowMenu.addItem(.separator())
        _ = add("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), to: windowMenu)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }
}

private struct WebViewHost: NSViewRepresentable {
    let model: BrowserModel
    func makeNSView(context: Context) -> WKWebView { model.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private struct ContentView: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pullLabel: String {
        if model.pullArmed { return model.pullUsesWheel ? "Stop scrolling to refresh" : "Release to refresh" }
        return model.pullUsesWheel ? "Keep scrolling to refresh" : "Pull to refresh"
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                WebViewHost(model: model)
                if !model.hasContent {
                    // Cover the empty web view until the first document draws, avoiding a white launch flash.
                    Color(nsColor: .windowBackgroundColor).allowsHitTesting(false)
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
                Text(model.status).font(.system(size: 11)).lineLimit(model.errorMessage == nil ? 1 : 2).foregroundStyle(.secondary)
                    .help(model.lastRefresh.map { "Page refreshed at \($0.formatted(date: .omitted, time: .standard))" } ?? model.status)
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

private struct ToolbarControls: View {
    @ObservedObject var model: BrowserModel
    let navigation: Bool

    var body: some View {
        HStack(spacing: 4) {
            if navigation {
                // Navigation stays available during loads; it simply starts a new one.
                Button(action: model.back) { Image(systemName: "chevron.left").frame(width: 24, height: 24) }
                    .disabled(!model.canGoBack)
                    .help("Back (⌘[)").accessibilityLabel("Back")
                Button(action: model.home) { Image(systemName: "house").frame(width: 24, height: 24) }
                    .help("Home (⌘1)").accessibilityLabel("Home")
            } else {
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise").frame(width: 24, height: 24) }
                    .disabled(model.loading)
                    .help("Refresh (⌘R)").accessibilityLabel("Refresh")
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
        .frame(width: 56, height: 26)
    }
}
