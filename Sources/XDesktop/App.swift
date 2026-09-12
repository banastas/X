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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate {
    private var window: NSWindow!
    private var model: BrowserModel!

    func applicationDidFinishLaunching(_ notification: Notification) {
        var fixture: URL?
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--fixture"), CommandLine.arguments.indices.contains(index + 1) {
            fixture = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        #endif
        model = BrowserModel(defaults: fixture == nil ? .standard : UserDefaults(suiteName: "as.banast.xdesktop.fixture")!, fixtureURL: fixture)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = fixture == nil ? "X" : "X · Test fixture"
        window.titleVisibility = .hidden
        window.toolbarStyle = .unifiedCompact
        window.titlebarSeparatorStyle = .none
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
        window.setFrameAutosaveName(fixture == nil ? "XMainWindow" : "XFixtureWindow")
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
        window.makeKeyAndOrderFront(nil)
        model.windowVisibilityChanged()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
    func windowWillClose(_ notification: Notification) { model.setSuspended("closed", paused: true) }
    func windowDidBecomeKey(_ notification: Notification) { model.setSuspended("closed", paused: false) }
    func windowDidMiniaturize(_ notification: Notification) { model.windowVisibilityChanged() }
    func windowDidDeminiaturize(_ notification: Notification) { model.windowVisibilityChanged() }
    func applicationDidHide(_ notification: Notification) { model.setSuspended("hidden", paused: true) }
    func applicationDidUnhide(_ notification: Notification) { model.setSuspended("hidden", paused: false) }
    func windowDidResignKey(_ notification: Notification) { model.cancelGesture() }

    @objc private func refresh() { model.refresh() }
    @objc private func home() { model.home() }
    @objc private func back() { model.back() }
    @objc private func toggleAutomatic() { model.toggleAutomatic() }

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
        let appMenu = NSMenu(title: "X")
        appMenu.addItem(withTitle: "About X", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide X", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit X", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        let editItem = NSMenuItem(); editItem.submenu = edit; menu.addItem(editItem)
        let view = NSMenu(title: "View")
        for (title, action, key) in [("Refresh", #selector(refresh), "r"), ("Home", #selector(home), "1"),
                                     ("Back", #selector(back), "["), ("Toggle Auto-refresh", #selector(toggleAutomatic), "p")] {
            let item = view.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = self
        }
        let viewItem = NSMenuItem(); viewItem.submenu = view; menu.addItem(viewItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem(); windowItem.submenu = windowMenu; menu.addItem(windowItem)
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
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                WebViewHost(model: model)
                if model.pullDistance > 0 {
                    Label(model.pullArmed ? (model.pullUsesWheel ? "Stop scrolling to refresh" : "Release to refresh") : "Pull to refresh", systemImage: "arrow.down")
                        .font(.caption).padding(10).background(.regularMaterial, in: Capsule())
                        .padding(.top, min(model.pullDistance / 3, 24))
                        .allowsHitTesting(false)
                } else if model.loading {
                    ProgressView().controlSize(.small).padding(10)
                        .background(.regularMaterial, in: Capsule()).padding(.top, 8).allowsHitTesting(false)
                }
            }
            Divider()
            HStack(spacing: 8) {
                Text(model.status).font(.system(size: 10)).lineLimit(model.errorMessage == nil ? 1 : 2).foregroundStyle(.secondary)
                    .help(model.lastRefresh.map { "Page refreshed at \($0.formatted(date: .omitted, time: .standard))" } ?? model.status)
                Spacer(minLength: 0)
                if model.errorMessage != nil { Button("Retry") { model.refresh() }.font(.caption) }
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
                Button(action: model.back) { Image(systemName: "chevron.left").frame(width: 24, height: 24) }
                    .disabled(!model.canGoBack || model.loading)
                    .help("Back (⌘[)").accessibilityLabel("Back")
                Button(action: model.home) { Image(systemName: "house").frame(width: 24, height: 24) }
                    .disabled(model.loading)
                    .help("Home (⌘1)").accessibilityLabel("Home")
            } else {
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise").frame(width: 24, height: 24) }
                    .disabled(model.loading)
                    .help("Refresh (⌘R)").accessibilityLabel("Refresh")
                Button(action: model.toggleAutomatic) {
                    Image(systemName: model.autoRefresh ? "pause" : "play").frame(width: 24, height: 24)
                }
                .help(model.autoRefresh ? "Pause auto-refresh (⌘P)" : "Resume auto-refresh (⌘P)")
                .accessibilityLabel(model.autoRefresh ? "Pause automatic refresh" : "Resume automatic refresh")
                .accessibilityValue(model.autoRefresh ? "On" : "Paused")
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .frame(width: 56, height: 26)
    }
}
