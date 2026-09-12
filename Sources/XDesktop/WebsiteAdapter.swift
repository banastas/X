import Foundation
import WebKit

struct WebsiteState: Decodable, Equatable {
    var home: Bool
    var recognized: Bool
    var ready: Bool
    var selected: Int
    var atTop: Bool
    var protected: Bool
    var reason: String
    var scrolling: Bool

    static let empty = WebsiteState(home: false, recognized: false, ready: false, selected: -1,
                                    atTop: false, protected: false, reason: "Waiting for X", scrolling: false)
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
