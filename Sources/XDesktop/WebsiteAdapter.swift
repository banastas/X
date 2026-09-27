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
    var reason: String
    /// Recent direct input or an open popover menu.
    var active: Bool

    static let empty = WebsiteState(home: false, recognized: false, ready: false, selected: -1, atTop: false,
                                    feedTop: true, protected: false, draft: false, failed: false, otherTab: false,
                                    reason: "Waiting for X", active: false)
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
/// rather than offer commands that silently do nothing.
final class XWebView: WKWebView {
    private static let unsupported: Set<String> = [
        "WKMenuItemIdentifierDownloadImage", "WKMenuItemIdentifierDownloadLinkedFile", "WKMenuItemIdentifierDownloadMedia"
    ]

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        for item in menu.items where Self.unsupported.contains(item.identifier?.rawValue ?? "") {
            menu.removeItem(item)
        }
        // Drop separators left leading, trailing, or doubled by the removals.
        var previousWasSeparator = true
        for item in menu.items {
            if item.isSeparatorItem && previousWasSeparator { menu.removeItem(item) } else { previousWasSeparator = item.isSeparatorItem }
        }
        if menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        super.willOpenMenu(menu, with: event)
    }
}
