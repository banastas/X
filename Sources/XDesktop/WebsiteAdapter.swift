import AppKit
import Foundation
import WebKit

struct WebsiteState: Decodable, Equatable {
    var home: Bool
    var recognized: Bool
    var ready: Bool
    var selected: Int
    var atTop: Bool
    /// The page itself is scrolled to the top of the feed, wherever the pointer is.
    var feedTop: Bool
    var protected: Bool
    /// Unsent text or an attached file that navigation could discard.
    var draft: Bool
    /// X is showing its own feed error.
    var failed: Bool
    /// Home is showing a pinned tab rather than For you or Following.
    var otherTab: Bool
    /// The reader picked a feed tab in this document, which outranks restoring the saved one.
    var feedChosen: Bool
    /// The saved feed could not be selected before the adapter's deadline.
    var restoreFailed: Bool
    var reason: String
    /// Recent direct input or an open popover menu.
    var active: Bool

    static let empty = WebsiteState(home: false, recognized: false, ready: false, selected: -1, atTop: false,
                                    feedTop: true, protected: false, draft: false, failed: false, otherTab: false,
                                    feedChosen: false, restoreFailed: false, reason: "Waiting for X", active: false)
    static func decode(_ body: Any) -> WebsiteState? {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body), data.count < 2048,
              let value = try? JSONDecoder().decode(Self.self, from: data),
              (-1...1).contains(value.selected), value.reason.count < 100 else { return nil }
        return value
    }
}

@MainActor
enum WebsiteAdapter {
    static let world = WKContentWorld.world(name: "XDesktop")
    static var script: String {
        get throws {
            let packaged = Bundle.main.resourceURL?.appendingPathComponent("XDesktop_XDesktop.bundle")
            let resources = packaged.flatMap { Bundle(url: $0) } ?? Bundle.module
            guard let url = resources.url(forResource: "Website", withExtension: "js") else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try String(contentsOf: url, encoding: .utf8)
        }
    }
}

/// WebKit's context-menu downloads require private delegate API. Hide those items
/// rather than offer commands that silently do nothing, and replace Download Image
/// with a public-API equivalent that saves the image beneath the click.
final class XWebView: WKWebView {
    private static let downloadImage = "WKMenuItemIdentifierDownloadImage"
    private static let unsupported: Set<String> = [
        downloadImage, "WKMenuItemIdentifierDownloadLinkedFile", "WKMenuItemIdentifierDownloadMedia"
    ]
    /// Starts a download of an image URL found beneath a context-menu click.
    var saveImage: ((URL) -> Void)?
    private var menuPoint: CGPoint?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        // The adapter hit-tests in CSS pixels from the top left of the page.
        let local = convert(event.locationInWindow, from: nil)
        let top = isFlipped ? local.y : bounds.height - local.y
        menuPoint = CGPoint(x: local.x / pageZoom, y: top / pageZoom)
        for (index, item) in menu.items.enumerated().reversed() where Self.unsupported.contains(item.identifier?.rawValue ?? "") {
            menu.removeItem(at: index)
            if item.identifier?.rawValue == Self.downloadImage, saveImage != nil {
                let save = NSMenuItem(title: "Save Image to Downloads", action: #selector(saveImageBeneathMenu), keyEquivalent: "")
                save.target = self
                menu.insertItem(save, at: index)
            }
        }
        // Drop separators left leading, trailing, or doubled by the removals.
        var previousWasSeparator = true
        for item in menu.items {
            if item.isSeparatorItem && previousWasSeparator { menu.removeItem(item) } else { previousWasSeparator = item.isSeparatorItem }
        }
        if menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        super.willOpenMenu(menu, with: event)
    }

    @objc private func saveImageBeneathMenu() {
        guard let point = menuPoint else { return }
        evaluateJavaScript("window.__xDesktop?.imageAt(\(point.x), \(point.y))", in: nil, in: WebsiteAdapter.world) { [weak self] result in
            guard case .success(let value) = result, let source = value as? String, let url = URL(string: source),
                  url.scheme == "https" else { NSSound.beep(); return }
            self?.saveImage?(url)
        }
    }
}
